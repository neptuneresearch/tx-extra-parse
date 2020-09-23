CREATE OR REPLACE PROCEDURE tx_extra_schema_indices() LANGUAGE plpgsql AS $$ 
BEGIN
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_schema_indices: Indices for transaction extra data parser schema
    */

    -- Drop indices
    --   tx_extra_data
    DROP INDEX IF EXISTS tx_extra_data_block_height_idx;
    DROP INDEX IF EXISTS tx_extra_data_tx_hash_idx;
    DROP INDEX IF EXISTS tx_extra_data_tx_is_coinbase_idx;
    DROP INDEX IF EXISTS tx_extra_data_tx_extra_tag_id_idx;
    DROP INDEX IF EXISTS tx_extra_data_size_idx;
    DROP INDEX IF EXISTS tx_extra_data_data_size_idx;
    DROP INDEX IF EXISTS tx_extra_data_data_idx;
    --   tx_extra_tag_list
    DROP INDEX IF EXISTS tx_extra_tag_list_block_height_idx;
    DROP INDEX IF EXISTS tx_extra_tag_list_tx_hash_idx;
    DROP INDEX IF EXISTS tx_extra_tag_list_tag_list_string_idx;

    RAISE NOTICE 'Indices dropped';

    -- Create indices
    --   tx_extra_data
    RAISE NOTICE 'Creating tx_extra_data_block_height_idx';
    CREATE INDEX tx_extra_data_block_height_idx ON public.tx_extra_data (block_height);
    RAISE NOTICE 'Creating tx_extra_data_tx_hash_idx';
    CREATE INDEX tx_extra_data_tx_hash_idx ON public.tx_extra_data (tx_hash);
    RAISE NOTICE 'Creating tx_extra_data_tx_is_coinbase_idx';
    CREATE INDEX tx_extra_data_tx_is_coinbase_idx ON public.tx_extra_data (tx_is_coinbase);
    RAISE NOTICE 'Creating tx_extra_data_tx_extra_tag_id_idx';
    CREATE INDEX tx_extra_data_tx_extra_tag_id_idx ON public.tx_extra_data (tx_extra_tag_id);
    RAISE NOTICE 'Creating tx_extra_data_size_idx';
    CREATE INDEX tx_extra_data_size_idx ON public.tx_extra_data (size);
    RAISE NOTICE 'Creating tx_extra_data_data_size_idx';
    CREATE INDEX tx_extra_data_data_size_idx ON public.tx_extra_data (data_size);
    RAISE NOTICE 'Creating tx_extra_data_data_idx';
    CREATE INDEX tx_extra_data_data_idx ON public.tx_extra_data (data);
    --   tx_extra_tag_list
    RAISE NOTICE 'Creating tx_extra_tag_list_block_height_idx';
    CREATE INDEX tx_extra_tag_list_block_height_idx ON public.tx_extra_tag_list (block_height);
    RAISE NOTICE 'Creating tx_extra_tag_list_tx_hash_idx';
    CREATE INDEX tx_extra_tag_list_tx_hash_idx ON public.tx_extra_tag_list (tx_hash);
    RAISE NOTICE 'Creating tx_extra_tag_list_tag_list_string_idx';
    CREATE INDEX tx_extra_tag_list_tag_list_string_idx ON public.tx_extra_tag_list (tag_list_string);
    
    RAISE NOTICE 'Indices created';
END;
$$;