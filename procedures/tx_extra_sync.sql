CREATE OR REPLACE PROCEDURE tx_extra_sync(
    status_only BOOLEAN DEFAULT FALSE,
    output_mode INTEGER DEFAULT NULL,
    coinbase_only BOOLEAN DEFAULT FALSE
) LANGUAGE plpgsql AS $$
DECLARE
    /*
        tx_extra_sync
        (c) 2021 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_sync: Starts tx_extra_process from the last height in tx_extra_data, ending at the last height available in the blockchain.
    */

    -- block_height_start: Last block height in tx_extra_data.
    block_height_start BIGINT;
    -- block_height_end: Last block height in blockchain.
    block_height_end BIGINT;
    -- block_count: Number of blocks in target range.
    block_count BIGINT;
BEGIN
    -- Read block_height_start
    SELECT MAX(block_height)
    INTO block_height_start
    FROM tx_extra_data;

    -- Read block_height_end
    SELECT MAX(height)
    INTO block_height_end 
    FROM monero;

    IF block_height_start IS NULL THEN
        -- tx_extra_data has never been synced, start at block 0
        block_height_start = 0;
    ELSE
        -- tx_extra_data has been synced before, start at the next block
        block_height_start = block_height_start + 1;
    END IF;

    -- +1: also count the starting block.
    block_count = block_height_end - block_height_start + 1;

    -- block_height_start - 1: this reports the last block in the table, not the next block to parse.
    RAISE NOTICE 'tx_extra_sync (Status): Height range % - % (% blocks)', block_height_start - 1, block_height_end, block_count;

    IF status_only THEN 
        RETURN;
    END IF;

    IF block_count = 0 THEN
        RAISE NOTICE 'tx_extra_sync (Status): Already synchronized';
        RETURN;
    END IF;

    CALL tx_extra_process(
        block_height_start,
        block_height_end,
        output_mode,
        coinbase_only
    );
END;
$$;