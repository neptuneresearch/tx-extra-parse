DROP MATERIALIZED VIEW IF EXISTS tx_extra_tag_count;

CREATE MATERIALIZED VIEW tx_extra_tag_count AS 
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_tag_count: Count each tag present per transaction
    */
    SELECT 
        D.block_height,
        D.tx_hash,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 1) AS n_padding,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 2) AS n_pubkey,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 3) AS n_extra_nonce,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 4) AS n_payment_id,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 5) AS n_payment_id8,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 6) AS n_merge_mining,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 7) AS n_pubkey_additional,
        COUNT(1) FILTER (WHERE D.tx_extra_tag_id = 8) AS n_mysterious_minergate
    FROM tx_extra_data D
    GROUP BY D.block_height, D.tx_hash
WITH NO DATA;