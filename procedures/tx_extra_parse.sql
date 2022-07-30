CREATE OR REPLACE PROCEDURE tx_extra_parse(
    tx_extra BYTEA,
    output_mode INTEGER DEFAULT NULL,
    block_height BIGINT DEFAULT NULL,
    tx_hash BYTEA DEFAULT NULL,
    tx_is_coinbase BOOLEAN DEFAULT NULL
) LANGUAGE plpgsql AS $$ 
DECLARE
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_parse: Transaction extra data parser
    */

    -- Run options
    --   write_enabled: Write output to tx_extra_data, tx_extra_tag, tx_extra_tag_list.
    write_enabled BOOLEAN = FALSE;
    --   debug_enabled: Log debug messages.
    debug_enabled BOOLEAN = FALSE;
    --   debug_buf_enabled: Log buffer updates (Not accessible through Output Mode).
    debug_buf_enabled BOOLEAN = FALSE;
    --   varint_size_mode: Read the size field as a CNS-003 variable-length integer.
    varint_size_mode BOOLEAN = TRUE;
    --   padding_tag_trim_mode: Padding tags: parse by trimming consecutive null bytes, leaving any non-null bytes for the next tag.
    padding_tag_trim_mode BOOLEAN = FALSE;

    -- State - tx_extra
    --   buf: Data source; data is unbuffered after each token is parsed.
    buf BYTEA;
    --   tag_list: List of tag bytes found in the order they occurred.
    tag_list BYTEA;
    --   tag_list_string: Disambiguate some cases of tag_list.
    tag_list_string BYTEA;

    -- State - tag
    --   tag_id: PK of the tx_extra_tag in use.
    tag_id BIGINT;
    --   tag_name: Name of the tx_extra_tag in use.
    tag_name VARCHAR;
    --   tag_value: Value of the matched tx_extra_tag (length can be > 1 byte if a longer byte sequence is matched).
    tag_value BYTEA;
    --   tag_len: How many bytes to be removed for the tag (can be > 1 if a longer byte sequence is matched).
    tag_len INTEGER;
    --   tag_fixed_size: Fixed size for a tag (cannot be used with any other size modifiers).
    tag_fixed_size INTEGER;
    --   tag_item_size: Item size for a tag (cannot be used with fixed size).
    tag_item_size INTEGER;
    --   tag_max_size: Max size for a tag (cannot be used with fixed size).
    tag_max_size INTEGER;
    --   tag_created: Set if a new tag was found and should be created.
    tag_created BOOLEAN;
    --   tag_byte: One byte representing tag (always the real tag byte, even if a longer byte sequence is matched).
    tag_byte BYTEA;

    -- State - data
    --   id: Output PK from inserting tx_extra_data.
    id BIGINT;
    --   size_len: How many bytes to be removed for the size (0 for fixed size, 1 else).
    size_len INTEGER;
    --   size_byte: Next byte representing size.
    size_byte BYTEA;
    --   size_byte_int: Integer value of next size byte.
    size_byte_int INTEGER;
    --   size_byte_int: All bytes representing size.
    size_bytes BYTEA;
    --   size: Total integer value of the size byte(s) (can be NULL for fixed size data).
    size INTEGER;
    --   data_size: Actual data size after applying all size modifiers (fixed, item, max).
    data_size INTEGER;
    --   data: Data value.
    data BYTEA;
    --   data_item: Current item of tag_item_size from an array data value.
    data_item BYTEA;
    --   size_last_buf_data: Actual data size that was unbuffered (can be less than data_size if less data than expected was found).
    size_last_buf_data INTEGER;
    --   buf_item: Array data value case; buffer for iterating by item size.
    buf_item BYTEA;

    --   buf_null_trim: Null padding tag case; temporarily holds a second copy of the buffer.
    buf_null_trim VARCHAR;
    --   buf_null_trim_len: Null padding tag case; length of null padding buffer.
    buf_null_trim_len INTEGER;

    -- State - tag list
    --   tag_list_string_byte: Temporarily holds the next byte for the tag list string.
    tag_list_string_byte BYTEA;
BEGIN
    -- Set mode
    write_enabled = (output_mode IS NULL OR output_mode = 2);
    debug_enabled = (output_mode IS NOT NULL AND output_mode <> 3);

    -- Initialize buffer
    buf = tx_extra;
    
    IF debug_enabled THEN
        RAISE NOTICE '(block %, tx %, %) $% %', 
            block_height,
            ENCODE(tx_hash, 'hex'),
            CASE tx_is_coinbase WHEN TRUE THEN 'TX_COINBASE' WHEN FALSE THEN 'TX_USER' WHEN NULL THEN 'TX_NO_TYPE' END, 
            OCTET_LENGTH(tx_extra), 
            ENCODE(tx_extra, 'hex');
    END IF;

    -- Next buffer
    WHILE OCTET_LENGTH(buf) > 0 LOOP
        -- Reset state
        tag_id = NULL;
        tag_name = NULL;
        tag_value = NULL;
        tag_len = NULL;
        tag_fixed_size = NULL;
        tag_item_size = NULL;
        tag_max_size = NULL;
        tag_created = NULL;
        tag_byte = NULL;
        id = NULL;
        size_len = NULL;
        size_byte = NULL;
        size_byte_int = NULL;
        size_bytes = NULL;
        size = NULL;
        data_size = NULL;
        data = NULL;
        data_item = NULL;
        size_last_buf_data = NULL;
        buf_null_trim = NULL;
        buf_item  = NULL;
        tag_list_string_byte = NULL;

        -- [Sub-field Tag]
        --   Try to find the tag that matches the longest prefix of the data buffer.
        --   The tag is usually the next single byte, but known tags can also use further bytes, including bytes from the size and value.
        SELECT
            T.tx_extra_tag_id,
            T."name",
            T.tag,
            OCTET_LENGTH(T.tag),
            T.fixed_size,
            T.item_size,
            T.max_size,
            FALSE
        INTO
            tag_id, 
            tag_name,
            tag_value,
            tag_len,
            tag_fixed_size,
            tag_item_size,
            tag_max_size,
            tag_created
        FROM tx_extra_tag T
        WHERE T.tag = SUBSTRING(buf FROM 1 FOR OCTET_LENGTH(T.tag))
            AND T.tag IS NOT NULL
        -- Match the longest byte sequence possible.
        ORDER BY OCTET_LENGTH(T.tag) DESC
        LIMIT 1;

        --   Also read the single tag byte.
        tag_byte = SUBSTRING(buf FROM 1 FOR 1);

        -- Tag not detected: Create a new tag from the next one byte
        IF tag_id IS NULL THEN
            tag_len = 1;

            tag_value = tag_byte;
            tag_fixed_size = NULL;
            tag_item_size = NULL;
            tag_max_size = NULL;
            tag_name = 'auto';
            tag_created = TRUE;
        END IF;

        -- Unbuffer tag
        buf = SUBSTRING(buf FROM 1 + tag_len);
        IF debug_buf_enabled THEN 
            RAISE NOTICE '  buf[%] tag->size: %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
        END IF;

        -- Null padding tag: determine size
        IF tag_value = '\x00' THEN
            IF padding_tag_trim_mode = TRUE THEN
                -- Trim mode for parsing null padding tags:
                --   Per CNS-005, null padding is supposed to be only allowed at the end and should finish the payload. 
                --   We could therefore exit early on the first NULL. But we will continue reading and see if any other tags were written after this null padding tag.
                --   We trim the front of the buffer by all NULLs, and let any data after the NULLs remain in the buffer.

                -- TRIM() cannot be done as BYTEA, it must be done in VARCHAR.
                buf_null_trim = TRIM(LEADING '0' FROM ENCODE(buf, 'hex'));
                buf_null_trim_len = LENGTH(buf_null_trim);
                
                -- Length of remainder should be even. 
                -- If it is odd, then the trim took a 0 from a non-null byte located after the null padding, so put it back ('0002' => '000' + '2' => '00' + '02').
                IF buf_null_trim_len % 2 = 1 THEN
                    buf_null_trim = '0' || buf_null_trim;
                    buf_null_trim_len = buf_null_trim_len + 1;
                END IF;
                -- Divide length by 2 to convert character length to byte length.
                buf_null_trim_len = buf_null_trim_len / 2;
                
                -- Set the Fixed Size to the number of NULL bytes found to be leading the buffer.
                tag_fixed_size = OCTET_LENGTH(buf) - buf_null_trim_len;
            
                IF debug_buf_enabled THEN
                    RAISE NOTICE '  nulltrim: buf: $% %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
                    RAISE NOTICE '  nulltrim: buf_null_trim: $% %', buf_null_trim_len, buf_null_trim;
                    RAISE NOTICE '  nulltrim: tag_fixed_size: %', tag_fixed_size;
                END IF;
            ELSE
                -- CNS-005 mode for parsing null padding tags:
                /*
                    1. padding is allowed only at the end of the Extra field
                        - See Rule 4
                    2. padding can only contain null bytes
                        - We know this isn't followed in practice (see coinbase tx on blocks 2105566 and 2105609).
                          Also, what would we do in this case: end the padding tag and try to parse another tag? We can't do that because of Rule 4.
                          So we aren't going to do anything when this rule fails.
                    3. the padding length is limited to 255 bytes
                        - See Rule 4
                    4. no explicit size is specified for padding (it occupies the remaining space of the Extra field)
                        - If it "occupies the remaining space", then: 
                            - it will BECOME the end of the extra field, so there is no need for Rule 1.
                            - there is no need for the Max_Size suggested by Rule 3.
                */
                
                -- Rule 4, "it occupies the remaining space of the Extra field":
                tag_fixed_size = OCTET_LENGTH(buf);
            END IF;
        END IF;

        -- [Sub-field Size]
        --   Determine size
        IF tag_fixed_size IS NOT NULL THEN
            -- Use fixed size
            size_len = 0;
            data_size = tag_fixed_size;
        ELSE
            -- Assert there is a size byte to parse
            IF OCTET_LENGTH(buf) > 0 THEN
                IF varint_size_mode = FALSE THEN
                    -- Parse single size byte as an integer (Naive mode)
                    size_byte = SUBSTRING(buf FROM 1 FOR size_len);
                    size_byte_int = ('x'||LPAD(ENCODE(size_byte, 'hex'), 8, '0'))::bit(32)::integer;

                    -- Update total
                    size_len = 1;
                    size_bytes = size_byte;
                    size = size_byte_int;

                    -- Unbuffer size byte
                    buf = SUBSTRING(buf FROM 1 + size_len);
                    IF debug_buf_enabled THEN 
                        RAISE NOTICE '  buf[%] size->data: %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
                    END IF;
                ELSE
                    -- Read size bytes until "a byte with the value less than 128 is found" (CNS-003 varint encoding)
                    size_len = 0;
                    size = 0;

                    -- This is set to enter the loop
                    size_byte_int = 128;

                    WHILE size_byte_int > 127 AND OCTET_LENGTH(buf) > 0 LOOP
                        -- Parse next byte as an integer
                        size_byte = SUBSTRING(buf FROM 1 FOR 1);
                        size_byte_int = ('x'||LPAD(ENCODE(size_byte, 'hex'), 8, '0'))::bit(32)::integer;
                        
                        -- Size byte debug
                        IF debug_enabled THEN 
                            RAISE NOTICE '    size[%] = %', size_len, size_byte_int;
                        END IF;

                        -- Update total
                        size_len = size_len + 1;
                        size_bytes = size_bytes || size_byte;
                        size = size + size_byte_int;

                        -- Unbuffer this byte
                        buf = SUBSTRING(buf FROM 2);
                        IF debug_buf_enabled THEN 
                            RAISE NOTICE '  varint_size: buf: $% %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
                        END IF;
                    END LOOP;

                    IF debug_buf_enabled THEN 
                        RAISE NOTICE '  buf[%] size->data: %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
                    END IF;
                END IF;

                -- Initialize data size to the parsed size
                data_size = size;

                -- Apply item size
                IF tag_item_size IS NOT NULL THEN
                    data_size = data_size * tag_item_size;
                END IF;

                -- Apply max size
                IF tag_max_size IS NOT NULL AND data_size > tag_max_size THEN
                    data_size = tag_max_size;
                END IF;
            ELSE
                -- No size byte
                size_len = 0;
            END IF;
        END IF;
        
        IF debug_enabled THEN
            RAISE NOTICE '  tag: % (TagLen=% SizeLen=% Size=% FixedSize=% MaxSize=% ItemSize=% DataSize=%)', ENCODE(tag_value, 'hex'), tag_len, size_len, size, tag_fixed_size, tag_max_size, tag_item_size, data_size;
        END IF;

        -- [Sub-field Data]
        IF (
            -- If we're writing a known NON-ARRAY tag, continue regardless of how much data is left in the buffer.
            (
                -- Known tag
                tag_id IS NOT NULL
                -- Not array tag
                AND tag_item_size IS NULL
            )
            -- If we're writing a known ARRAY tag, validate the size (but allow 0): we will only create a new tag if the size byte is plausible.
            OR (
                -- Known tag
                tag_id IS NOT NULL
                -- Array tag
                AND tag_item_size IS NOT NULL
                -- Data size can be 0
                AND data_size IS NOT NULL
                -- But it has to be accurate
                AND OCTET_LENGTH(buf) >= data_size
            )
            -- If we're not writing a known NON-ARRAY tag, validate the size (not allowing 0): we will only create a new tag if the size byte is plausible.
            OR (
                -- Unknown tag (also implies non-array tag, because Item Size can only be set for known tags)
                tag_id IS NULL
                -- a. data_size must be non-empty: there must have been a size byte, and it must have been greater than 0.
                --      data_size IS NULL if fixed_size is not in use (configured for a known tag or null padding case) and there was no size byte.
                --      data_size = 0 if fixed_size = 0 or if the size byte was 0.
                AND COALESCE(data_size, 0) > 0 
                -- b. There should be AT LEAST data_size left in the buffer. Otherwise, the size byte is inaccurate,
                --    which then means it probably wasn't a size byte, which then means we might not have a real unknown tag.
                AND OCTET_LENGTH(buf) >= data_size
            )
         ) THEN           
            -- Known tag with no data: write NULL data instead of empty string
            IF tag_id IS NOT NULL AND data_size = 0 THEN
                data = NULL;
            ELSE
                -- Known tag: this may return less data than requested
                -- New tag: this will return the exact amount of data requested, since that was validated
                data = SUBSTRING(buf FROM 1 FOR data_size);
            END IF;

            -- New tag: create tag
            IF tag_created AND write_enabled THEN
                INSERT INTO tx_extra_tag (name, tag)
                VALUES (tag_name, tag_value)
                RETURNING tx_extra_tag_id INTO tag_id;
            END IF;

            -- Write data records
            --   Known tag: If item_size is in use, assert the buffer is non-empty
            IF tag_item_size IS NOT NULL AND (COALESCE(data_size, 0) > 0 AND OCTET_LENGTH(buf) > 0) THEN
                -- Write each item as a separate data record
                buf_item = data;
                WHILE OCTET_LENGTH(buf_item) > 0 LOOP
                    -- Read item
                    data_item = SUBSTRING(buf_item FROM 1 FOR tag_item_size);

                    -- Insert item
                    IF write_enabled THEN
                        INSERT INTO tx_extra_data (block_height, tx_hash, tx_is_coinbase, tx_extra_tag_id, size, data_size, data)
                        VALUES (block_height, tx_hash, tx_is_coinbase, tag_id, tag_item_size, tag_item_size, data_item)
                        RETURNING tx_extra_data_id INTO id;
                    ELSE
                        id = 0;
                    END IF;

                    -- Item data debug
                    IF debug_enabled THEN 
                        RAISE NOTICE '    #% % $% %', id, tag_name, tag_item_size, ENCODE(data_item, 'hex');
                    END IF;

                    -- Unbuffer item
                    buf_item = SUBSTRING(buf_item FROM 1 + tag_item_size);
                END LOOP;
            -- Known tag: either item_size is not in use or there is no data
            -- New tag: always (and again, per validation, it is given that size = data_size)
            ELSE
                -- Write one data record
                IF write_enabled THEN
                    INSERT INTO tx_extra_data (block_height, tx_hash, tx_is_coinbase, tx_extra_tag_id, size, data_size, data)
                    VALUES (block_height, tx_hash, tx_is_coinbase, tag_id, size, data_size, data)
                    RETURNING tx_extra_data_id INTO id;
                ELSE
                    id = 0;
                END IF;
            END IF;

            -- New tag: add origin tag id to the tag name
            IF tag_created THEN
                UPDATE tx_extra_tag SET "name" = id
                WHERE tx_extra_tag_id = tag_id;
                
                IF debug_enabled THEN 
                    RAISE NOTICE '  Tag created #% = %', id, ENCODE(tag_value, 'hex');
                END IF;
            END IF;
        ELSE
            -- Remainder case: we've found an unknown tag, and the size byte is missing or invalid.
            -- This data ends the notion of parsing the standard format for this transaction.
            -- Write the remainder of the buffer to a NULL tag with NULL size, and end parsing for the transaction.
            tag_name = 'remainder';

            -- This executes in 3 cases:
            -- 1. data_size IS NULL
            --      data_size IS NULL if fixed_size is not in use (configured for a known tag or null padding case) and there was no size byte.
            --      This isn't a known tag or null padding case, so maybe there was no size byte.
            -- 2. data_size = 0
            --      data_size = 0 if fixed_size = 0 or if the size byte was 0.
            --      There is no fixed size, so maybe the size byte was 0.
            -- 3. OCTET_LENGTH(buf) < data_size
            --      If there was a size byte, there wasn't enough data.
            
            -- There was definitely a tag byte (not a tag, but in the tag position); record it as data.
            data = tag_byte;

            -- There were possibly size byte(s) (not a size, but in the size position); record it as data.
            IF size_bytes IS NOT NULL THEN
                data = data || size_bytes;
            END IF;

            -- Finally, consume the rest of the buffer.
            IF COALESCE(data_size, 0) > 0 THEN
                data = data || SUBSTRING(buf FROM 1);

                data_size = NULL;
            END IF;

            -- Write the data record
            IF write_enabled THEN
                INSERT INTO tx_extra_data (block_height, tx_hash, tx_is_coinbase, tx_extra_tag_id, size, data_size, data)
                VALUES (block_height, tx_hash, tx_is_coinbase, NULL, NULL, NULL, data)
                RETURNING tx_extra_data_id INTO id;
            ELSE
                id = 0;
            END IF;

            -- Tag list: use the special byte FF to denote Remainder case
            tag_byte = '\xFF';
        END IF;

        -- Tag list
        tag_list = CASE WHEN tag_list IS NULL THEN tag_byte ELSE tag_list || tag_byte END;

        -- Tag list string: Represent some cases differently
        tag_list_string_byte = CASE
                -- payment_id8: Distinguish from payment_id and extra_nonce ("02") by inverting the number
                WHEN tag_name = 'payment_id8' THEN '\x20'
                -- extra_nonce: Distinguish from payment_id and payment_id8 ("02") by repeating the number
                WHEN tag_name = 'extra_nonce' THEN '\x22'
                -- Default case: Use tag byte
                ELSE tag_byte
            END;
        tag_list_string = CASE WHEN tag_list_string IS NULL THEN tag_list_string_byte ELSE tag_list_string || tag_list_string_byte END;

        -- Non-array data debug (or Array data size 0, because "Write each item as a separate data record" never ran)
        IF debug_enabled AND (tag_item_size IS NULL OR data_size = 0) THEN 
            RAISE NOTICE '    #% % $% %', id, tag_name, data_size, ENCODE(data, 'hex');
        END IF;

        -- Consume tag data: this uses the actual length returned, which may be less than was requested by data_size
        size_last_buf_data = OCTET_LENGTH(data);
        IF size_last_buf_data > 0 THEN
            buf = SUBSTRING(buf FROM 1 + size_last_buf_data);
        END IF;

        IF debug_buf_enabled THEN 
            RAISE NOTICE '  buf[%] data->tag: %', OCTET_LENGTH(buf), ENCODE(buf, 'hex');
        END IF;

        -- Re-evaluate the loop condition: if there is more data, parse the next tag
    END LOOP;

    -- Buffer exhausted

    -- Write the tag list record
    IF debug_enabled THEN 
        RAISE NOTICE '  tag_list: %', ENCODE(tag_list, 'hex');
        RAISE NOTICE '  tag_list_string: %', ENCODE(tag_list_string, 'hex');
    END IF;

    IF tag_list IS NOT NULL AND write_enabled THEN
        INSERT INTO tx_extra_tag_list (block_height, tx_hash, tx_is_coinbase, tag_list, tag_list_string)
        VALUES (block_height, tx_hash, tx_is_coinbase, tag_list, tag_list_string);
    END IF;

    -- Commit the database transaction
    --   (This is important in the context of tx_extra_process(), so that if some tx_extra_parse() call fails, all output up to that point was committed.)
    COMMIT;
END;
$$;