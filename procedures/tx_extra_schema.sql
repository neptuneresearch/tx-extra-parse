CREATE OR REPLACE PROCEDURE tx_extra_schema() LANGUAGE plpgsql AS $$ 
BEGIN
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_schema: Setup schema for transaction extra data parser
    */

    -- Drop schema
    DROP TABLE IF EXISTS tx_extra_data;
    DROP TABLE IF EXISTS tx_extra_tag;
    DROP TABLE IF EXISTS tx_extra_tag_list;
    RAISE NOTICE 'tx_extra_schema: Schema dropped';

    -- Create schema
    --   tx_extra_tag: Tags
    CREATE TABLE tx_extra_tag (
        "tx_extra_tag_id" BIGSERIAL PRIMARY KEY,
        "name" VARCHAR NOT NULL,
        "tag" BYTEA NOT NULL,
        "fixed_size" INTEGER NULL,
        "item_size" INTEGER NULL,
        "max_size" INTEGER NULL
    );

    INSERT INTO tx_extra_tag (name, tag) VALUES ('padding', '\x00');
    INSERT INTO tx_extra_tag (name, tag, fixed_size) VALUES ('pubkey', '\x01', 32);
    INSERT INTO tx_extra_tag (name, tag, max_size) VALUES ('extra_nonce', '\x02', 255);
    INSERT INTO tx_extra_tag (name, tag, fixed_size) VALUES ('payment_id', '\x022100', 32);
    INSERT INTO tx_extra_tag (name, tag, fixed_size) VALUES ('payment_id8', '\x020901', 8);
    INSERT INTO tx_extra_tag (name, tag) VALUES ('merge_mining', '\x03');
    INSERT INTO tx_extra_tag (name, tag, item_size) VALUES ('pubkey_additional', '\x04', 32);
    INSERT INTO tx_extra_tag (name, tag) VALUES ('mysterious_minergate', '\xDE');

    --   tx_extra_data: Data
    CREATE TABLE tx_extra_data (
        "tx_extra_data_id" BIGSERIAL PRIMARY KEY,
        "block_height" BIGINT NULL,
        "tx_hash" BYTEA NULL,
        "tx_is_coinbase" BOOLEAN NULL,
        "tx_extra_tag_id" INT NULL REFERENCES tx_extra_tag (tx_extra_tag_id),
        "size" INTEGER NULL,
        "data_size" INTEGER NULL,
        "data" BYTEA NULL
    );

    --   tx_extra_tag_list: Tag Lists
    CREATE TABLE tx_extra_tag_list (
        "tx_extra_tag_list_id" BIGSERIAL PRIMARY KEY,
        "block_height" BIGINT NULL,
        "tx_hash" BYTEA NULL,
        "tx_is_coinbase" BOOLEAN NULL,
        "tag_list" BYTEA NOT NULL,
        "tag_list_string" BYTEA NOT NULL
    );

    RAISE NOTICE 'tx_extra_schema: Schema created';
END;
$$;