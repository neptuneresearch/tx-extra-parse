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

    -- Validate heights
    --  tx_extra_data: If no height, never synced, start from 0
    IF block_height_start IS NULL THEN
        block_height_start = 0;
    END IF;

    block_count = block_height_end - block_height_start;

    RAISE NOTICE 'tx_extra_sync: Height range % - % (% blocks)', block_height_start, block_height_end, block_count;

    IF status_only THEN 
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