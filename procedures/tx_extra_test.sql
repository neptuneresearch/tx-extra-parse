CREATE OR REPLACE PROCEDURE tx_extra_test(
    test_id INTEGER
) LANGUAGE plpgsql AS $$
BEGIN
    /*
        tx_extra_parse
        (c) 2020 Neptune Research
        SPDX-License-Identifier: BSD-3-Clause

        tx_extra_test: Transaction extra data parser unit test suite
    */

    -- tx_extra_process
    --   Process 1 block in DEBUG mode
    IF test_id = 1 THEN
        CALL tx_extra_process(1220516, 1220516, 1);
    END IF;

    --   Process 1 block in WRITE mode
    IF test_id = 2 THEN
        CALL tx_extra_process(1220516, 1220516);
    END IF;

    --   Process 2 blocks in DEBUG mode
    IF test_id = 3 THEN
        CALL tx_extra_process(1034150, 1034151, 1);
    END IF;

    --   Process 2 blocks COINBASE ONLY in DEBUG mode
    IF test_id = 4 THEN
        CALL tx_extra_process(1515616, 1515617, 1, TRUE);
    END IF;

    -- tx_extra_parse
    --   Common tags
    --     Parse 0102 in DEBUG mode
    IF test_id = 5 THEN
        CALL tx_extra_parse('\x010102030401020304010203040102030401020304010203040102030401020304022100aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd', 1);
    END IF;

    --   Array tag
    --     Parse 04 in DEBUG mode
    IF test_id = 6 THEN
        CALL tx_extra_parse('\x04020102030401020304010203040102030401020304010203040102030401020304aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd', 1);
    END IF;

    --     Parse known array tag with 0 size (see tx #2 02E4F925564EB9A6DC68D59A455A1AB8F67AA5A4B0027A7AC7BA2556E9342759)
    IF test_id = 7 THEN
        CALL tx_extra_process(1440194, 1440194, 1);
    END IF;

    --   Padding tag
    --     Parse single padding tag case in DEBUG mode
    IF test_id = 8 THEN
        CALL tx_extra_process(22542, 22542, 1, TRUE);
    END IF;

    --     Parse padding tag interrupted by valid tags in DEBUG mode
    IF test_id = 9 THEN
        CALL tx_extra_parse('\x000000000201aa00000000000201bb', 1);
    END IF;

    --     Parse padding tag interrupted by invalid tags in DEBUG mode
    IF test_id = 10 THEN
        CALL tx_extra_parse('\x000000001000000000003000', 1);
    END IF;

    --     Parse known padding tag cases which include non-null bytes
    IF test_id = 11 THEN
        CALL tx_extra_process(2105566, 2105566, 1, TRUE);
        CALL tx_extra_process(2105609, 2105609, 1, TRUE);
    END IF;

    --   Malformed tag
    --     Remainder case T: see tx #1 f6cff1edd1a7861ed13d494dd4ae7c4a7f42b5c3bf91457310d2166722c1316f)
    IF test_id = 12 THEN
        CALL tx_extra_process(2012557, 2012557, 1);
    END IF;

    --     Remainder case TS
    IF test_id = 13 THEN
        CALL tx_extra_parse('\x0c01', 1);
    END IF;

    --     Parse known item_size tag with invalid size (see tx E87C675A85F34ECAC58A8846613D25062F1813E1023C552B705AFAD32B972C38)
    IF test_id = 14 THEN
        CALL tx_extra_process(1610845, 1610845, 1);
    END IF;

    --   Size field
    --     Test varint size decoding
    IF test_id = 15 THEN
        CALL tx_extra_parse('\x02800Faabbccdd', 1);
    END IF;
END;
$$;