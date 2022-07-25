CREATE OR REPLACE PROCEDURE tx_extra_process(
    block_height_start BIGINT, 
    block_height_end BIGINT DEFAULT NULL,
    output_mode INTEGER DEFAULT NULL,
    coinbase_only BOOLEAN DEFAULT FALSE
) LANGUAGE plpgsql AS $$
DECLARE
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_process: Iterates a transaction table in ranges, invoking tx_extra_parse() on the tx_extra data in each transaction.
    */

    -- Run options
    --   debug_enabled: Log debug messages.
    debug_enabled BOOLEAN = FALSE;

    -- State
    --   rec_extra: Current transaction record.
    rec_extra RECORD;
    --   coinbase_height: Last block height read; when this changes, the coinbase of the current block is sent to the parser.
    coinbase_height BIGINT;
BEGIN
    -- block_height_end: If not specified, read max height
    IF block_height_end IS NULL THEN
        SELECT MAX(height) 
        INTO block_height_end 
        FROM monero block;
    END IF;

    -- Coinbase counter: initialize
    coinbase_height = 0;

    FOR rec_extra IN
        SELECT 
            block.height,
            tx.hash,
            tx.extra,
            (miner_tx).hash AS coinbase_hash,
            (miner_tx).extra AS coinbase_extra
        FROM monero block
        -- LEFT JOIN: Every block has 1 coinbase transaction and 0 or more user transactions
        LEFT JOIN LATERAL unnest(block.transactions) tx(hash, version, unlock_time, vin, vout, extra, fee) ON TRUE
        WHERE block.height >= block_height_start AND (block_height_end IS NULL OR block.height <= block_height_end)
        ORDER BY block.height ASC
    LOOP
        IF debug_enabled THEN
            RAISE NOTICE 'Coinbase height %', coinbase_height;
        END IF;

        -- Parse coinbase on block height change
        IF coinbase_height <> rec_extra.height THEN
            IF debug_enabled THEN
                RAISE NOTICE 'Block height changed';
            END IF;

            IF rec_extra.coinbase_extra IS NOT NULL AND OCTET_LENGTH(rec_extra.coinbase_extra) > 0 THEN
                RAISE NOTICE '% %% % / % COINBASE', 
                    (((rec_extra.height - block_height_start) * 100) / GREATEST(block_height_end - block_height_start, 1)), 
                    rec_extra.height, 
                    block_height_end;
                
                CALL tx_extra_parse(
                    rec_extra.coinbase_extra,
                    output_mode,
                    rec_extra.height,
                    rec_extra.coinbase_hash,
                    TRUE
                );
            END IF;

            -- Coinbase counter: update
            coinbase_height = rec_extra.height;
            IF debug_enabled THEN
                RAISE NOTICE 'Coinbase height %', coinbase_height;
            END IF;

            -- If parser is also writing debug messages, add two empty lines after transactions, for spacing
            IF (output_mode IS NOT NULL AND output_mode <> 3) THEN
                RAISE NOTICE '';
                RAISE NOTICE '';
            END IF;
        END IF;

        -- Parse user transactions
        IF coinbase_only = FALSE AND rec_extra.extra IS NOT NULL AND OCTET_LENGTH(rec_extra.extra) > 0 THEN
            RAISE NOTICE '% %% % / %', 
                (((rec_extra.height - block_height_start) * 100) / GREATEST(block_height_end - block_height_start, 1)), 
                rec_extra.height, 
                block_height_end;
        
            CALL tx_extra_parse(
                rec_extra.extra,
                output_mode,
                rec_extra.height,
                rec_extra.hash,
                FALSE
            );

            -- If parser is also writing debug messages, add two empty lines after transactions, for spacing
            IF (output_mode IS NOT NULL AND output_mode <> 3) THEN
                RAISE NOTICE '';
                RAISE NOTICE '';
            END IF;
        END IF;
    END LOOP;
END;
$$;