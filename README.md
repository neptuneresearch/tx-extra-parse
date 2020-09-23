# tx_extra_parse
```tx_extra_parse``` is a PL/pgSQL stored procedure for PostgreSQL which parses Monero transaction extra data (```tx_extra```) into individual data records.

---
## Table of Contents
- [Overview](#Overview)
- [Requirements](#Requirements)
- [Installation](#Installation)
- [Procedure tx_extra_parse()](#Procedure_tx_extra_parse)
  - [Parameters](#Parameters)
  - [Output Modes](#Output_Modes)
  - [Examples](#Examples)
- [Schema](#Schema)
  - [Table tx_extra_data](#Table_tx_extra_data)
    - Notes
    - Indices
  - [Table tx_extra_tag](#Table_tx_extra_tag)
    - Default Data
    - Notes
  - [Table tx_extra_tag_list](#Table_tx_extra_tag_list)
    - Tag List String
    - Indices
- [Procedure tx_extra_process()](#Procedure_tx_extra_process)
    - Parameters
    - Examples
- [Procedure tx_extra_test()](#Procedure_tx_extra_test)
    - Parameters
    - Tests
    - Test utilities
- [Procedure tx_extra_schema()](#Procedure_tx_extra_schema)
- [Procedure tx_extra_schema_indices()](#Procedure_tx_extra_schema_indices)
- [Materialized View tx_extra_tag_count](#Materialized_View_tx_extra_tag_count)
- [References](#References)
  - [Results](#Results)


---
# Overview

```tx_extra``` is a field on Monero transactions which stores additional data such as:
- Public key(s) for the transaction
- Payment ID (unencrypted or encrypted)
- Information used by miners and mining pools

There is no verification for data stored in ```tx_extra```. However, data stored in this field is commonly written in a standard format, described in CryptoNote Standard 005 [[1]](#References). 

```tx_extra_parse``` is a PostgreSQL implementation of a parser for this standard format. Per the Standard:

```
   The Extra field can contain several sub-fields. Each sub-field
   contains a sub-field tag followed by sub-field content. The sub-field
   tag indicates the nature of the data. In some cases the size of the
   data is implied by the sub-field tag itself (Figure 3b). In other
   cases the size is specified explicitly after the sub-field tag
   (Figure 3c).

   +-------+--------+
   |  Tag  |  Data  |
   +-------+--------+

           Figure 3b: Data size implied by the sub-field tag


   +-------+--------+--------+
   |  Tag  |  Size  |  Data  |
   +-------+--------+--------+

               Figure 3c: Data size specified explicitly  
```

This parser interprets the standard format against a lookup table (Table ```tx_extra_tag```) which defines the sub-field tags used in the Monero core software [[4]](#References). Although this parser is designed for Monero, this could also theoretically parse ```tx_extra``` data for other CryptoNote-based currencies, given their sub-field tag specification.
 
 Using PL/pgSQL binary string functions, the parser sequentially reads each byte in the ```tx_extra``` data, and writes the individual sub-fields to a table (Table ```tx_extra_data```). A summary of the tags used in a given transaction, in their original order, is also written (Table ```tx_extra_tag_list```). Unknown sub-field tags are learned when they are first seen.

An individual transaction's extra data field can be parsed by the stored procedure ```tx_extra_parse()```. The blockchain, when stored in some table, can be input to the parser by calling the stored procedure ```tx_extra_process()```.


## Example

1. Consider the following ```tx_extra``` data for some transaction.

```
010A0A0A0A0B0B0B0B0C0C0C0C0D0D0D0D0A0A0A0A0B0B0B0B0C0C0C0C0D0D0D0D020A0102030405060708090A00000000
```

2. Call the parser.

```
CALL tx_extra_parse('\x010A0A0A0A0B0B0B0B0C0C0C0C0D0D0D0D0A0A0A0A0B0B0B0B0C0C0C0C0D0D0D0D020A0102030405060708090A00000000');
```

3. The parser wrote these records to the database.

To table ```tx_extra_data```:
  
| tx_extra_data_id | tx_extra_tag_id | size | data_size | data |  
| - | - | - | - | - |  
| 1 | 2 (pubkey) | 32 | 32 | 0a0a0a0a0b0b0b0b0c0c0c0c0d0d0d0d0a0a0a0a0b0b0b0b0c0c0c0c0d0d0d0d |  
| 2 | 5 (extra_nonce) | 10 | 10 | 0102030405060708090a |  
| 3 | 1 (padding) | 3 | 3 | 000000 |  


To table ```tx_extra_tag_list```:

| tx_extra_tag_list_id | tag_list | tag_list_string |
| - | - | - |
| 1 | 010200 | 010200 |


---
# Requirements

- PostgreSQL 11+
  - These procedures and tables were written and tested with PostgreSQL versions 11.5 and 12.3. Older versions may work.

- Monero blockchain data
  - ```tx_extra_parse()```: Requires only ```tx_extra``` data. 
  
    Since the ```tx_extra``` data is provided to ```tx_extra_parse()``` as a ```CALL``` parameter, it does not necessarily have to originate from the same database where ```tx_extra_parse()``` is installed (or any database at all). For instance, an external program which has its own way of sourcing ```tx_extra``` data could connect to PostgreSQL and call ```tx_extra_parse()``` to parse it.
  
  - ```tx_extra_process()```: Requires a table of blocks, where each block row includes an array-typed column of transactions, and each transaction row includes a ```tx_extra``` column. 
  
    This method is designed for use when ```tx_extra``` data is in the same database where ```tx_extra_parse()``` is installed. This procedure is designed specifically to work with the Monero schema in ```coinmetrics-export``` [[5]](#References), but it could be ported to any schema that has the sufficient data.



---
# Installation
## Using SQL Files
To install a SQL file, open the file and run the entire file contents in your PostgreSQL database using a PostgreSQL administration tool.

Example for PostgreSQL CLI, where ```DB_NAME``` is the name of the target database, and ```FILE.SQL``` is the source filename:

  ```
  psql -d DB_NAME -f FILE.SQL
  ```

## Stored Procedures

This package includes the following stored procedures.

| File | Description |
| - | - |
| `tx_extra_parse.sql` | Parser |
| `tx_extra_process.sql` | Blockchain processor |
| `tx_extra_schema.sql` | Schema setup |
| `tx_extra_schema_indices.sql` | Indices setup |
| `tx_extra_test.sql` | Unit tests |

Installation must proceed in this order:

1. ```tx_extra_schema```: This sets up the schema (tables and default data), which all of the other stored procedures depend on.

    a. Use the file ```tx_extra_schema.sql``` to create the stored procedure ```tx_extra_schema()```.

    ```
    psql -d DB_NAME -f tx_extra_schema.sql
    ```

    b. Execute the stored procedure ```tx_extra_schema()```.

    > WARNING: If any of the following tables already exist, they will be replaced.  
       - ```tx_extra_data```  
       - ```tx_extra_tag```  
       - ```tx_extra_tag_list```

    ```
    CALL tx_extra_schema();
    ```


2. Install the other stored procedures, in any order. They don't need to be executed during installation.
  
    - ```tx_extra_parse.sql```

    - ```tx_extra_process.sql```

    - *Optional/Developer: Unit tests.* ```tx_extra_test.sql```


3. Indices on output tables are created by the stored procedure ```tx_extra_schema_indices```. Install ```tx_extra_schema_indices.sql``` the same as Step 1.

      a. Use the file ```tx_extra_schema_indices.sql``` to create the stored procedure ```tx_extra_schema_indices```.

      ```
      psql -d DB_NAME -f tx_extra_schema_indices.sql
      ```

      b. WHEN READY to create indices on output tables, execute the stored procedure ```tx_extra_schema_indices()```.

      ```
      CALL tx_extra_schema_indices();
      ```

      - Indices make queries faster, so they are recommended to be installed BEFORE querying any output tables. 
      - However, after their initial creation, indices are updated whenever tables are updated. If you're going to parse the entire blockchain, wait to install the indices until AFTER parsing all data, so that this extended parse operation doesn't waste time updating the indices after each individual transaction.


## Materialized Views
This package includes the following materialized views.

| File | Description |
| - | - |
| `tx_extra_tag_count.sql` | Tag count per transaction |

The materialized view is created `WITH NO DATA` and must be refreshed before usage.

### Refreshing data
Whenever new data is available in Table `tx_extra_data`, refresh the materialized view to update its data:

```
REFRESH MATERIALIZED VIEW tx_extra_tag_count;
```


## Reset output tables
To reset all output tables to zero rows, re-run ```tx_extra_schema()```.

  ```
  CALL tx_extra_schema();
  ```

---
# Procedure ```tx_extra_parse()```
Parses the extra data of a transaction, saving the individual extra sub-fields to table ```tx_extra_data```, and the extra sub-field tag ordering to ```tx_extra_tag_list```.

```
CALL tx_extra_parse(tx_extra, output_mode, block_height, tx_hash, tx_is_coinbase);
```

## Parameters

| Parameter | Type | Description |
| - | - | - |
| ```tx_extra``` | ```BYTEA``` | ```tx_extra``` data to parse. |
| ```output_mode``` | ```INTEGER``` | *Optional*: See "Output Modes". Defaults to ```NULL``` (Write mode). |
| ```block_height``` | ```BIGINT``` | *Optional*: block height of originating transaction. Not used by the parser; this value is stored in the output record for reference. Defaults to ```0```. |
| ```tx_hash``` | ```BYTEA``` | *Optional*: transaction hash of originating transaction. Not used by the parser; this value is stored in the output record for reference. Defaults to ```NULL```. |
| ```tx_is_coinbase``` | ```BOOLEAN``` | *Optional*: type of originating transaction (```TRUE``` for coinbase, ```FALSE``` for user). Not used by the parser; this value is stored in the output record for reference. Defaults to ```NULL```. |

## Output Modes

| ```output_mode``` | Name | Description |
| - | - | - |
| ```NULL``` | Write | Writes results to tables. *Note*: Writing is additive and will always create new records; previous results stored for the same ```block_height, tx_hash``` will never be overwritten. |
| ```1``` | Debug | Writes verbose parser log to "console" (via ```RAISE NOTICE```) |
| ```2``` | Write and Debug | Combines Write and Debug modes |
| ```3``` | No Output | Silent run (used to isolate error messages) |

## Examples

```
-- Parse mock tx_extra data (Public key, Payment id unencrypted) 
--   for mock transaction hash '33...' in block 2000000 
--   in Write mode
CALL tx_extra_parse('\x010102030401020304010203040102030401020304010203040102030401020304022100aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd', NULL, 2000000, '\x33333333333333333333333333333333');

-- Parse mock tx_extra data (Additional public keys) in Debug mode 
CALL tx_extra_parse('\x04020102030401020304010203040102030401020304010203040102030401020304aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd', 1);
```


--- 
# Schema

## Table ```tx_extra_data```
Individual sub-fields parsed from a transaction's extra data.

Identified by ```tx_extra_data_id```, an incrementing number.

Block Height and Transaction Hash link a data record back to its origin on the blockchain. These values are not required and have no foreign key integrity.

| Column | Description | Type | Constraint |
| - | - | - | - |
| ```tx_extra_data_id``` | Identity | ```BIGSERIAL``` | ```PRIMARY KEY``` |
| ```block_height``` | Block height | ```BIGINT``` | - |
| ```tx_hash``` | Transaction hash | ```BYTEA``` | - |
| ```tx_is_coinbase``` | Transaction is coinbase *(see Note 1)* | ```BOOLEAN``` | - |
| ```tx_extra_tag_id``` | Tag | ```INTEGER``` | ```FOREIGN KEY (tx_extra_tag)``` *(see Note 3)* |
| ```size``` | Recorded size | ```INTEGER``` | - |
| ```data_size``` | Computed data size *(see Note 2)* | ```INTEGER``` | - |
| ```data``` | Tag data | ```BYTEA``` | - |

### Notes

1. **Transaction is coinbase**: Coinbase transactions use transaction extra data for different purposes than user transactions, so they are important to differentiate.

2. **Data size**: Actual size may be different from recorded size if the amount of bytes actually available to be read for the data value are less than the size calculation expected.

3. **Null tag id**: Malformed sub-field data, even if beginning with a known tag byte, will be recorded under the NULL tag id.
  The following cases are identified: 

  - Remainder case 'T': Tag byte only, no size or data
  - Remainder case 'TS': Tag byte and size byte, but no data
  - Known array tag with insufficient data for determined `data_size`
  - Unknown tag with insufficient data for determined `data_size`

### Indices
```tx_extra_schema_indices()``` includes the following indices for ```tx_extra_data```.

- ```tx_extra_data_block_height_idx```: index on ```{ block_height }```
- ```tx_extra_data_tx_hash_idx```: index on ```{ tx_hash }```
- ```tx_extra_data_tx_is_coinbase_idx```: index on ```{ tx_is_coinbase }```
- ```tx_extra_data_tx_extra_tag_id_idx```: index on ```{ tx_extra_tag_id }```
- ```tx_extra_data_size_idx```: index on ```{ size }```
- ```tx_extra_data_data_size_idx```: index on ```{ data_size }```
- ```tx_extra_data_data_idx```: index on ```{ data }```


## Table ```tx_extra_tag```
Lookup table of known tags.

To read the next tag, the parser queries this table for the ```tag``` value which matches the longest possible sequence of bytes at the beginning of the parse buffer. The tag is usually the next single byte, but this query permits known tags to use any number of bytes, including bytes from the size and value. For example, ```payment_id```, ```payment_id8```, and ```extra_nonce``` all start with the byte value ```02```. ```payment_id``` and ```payment_id8``` are subclasses of ```extra_nonce```, differentiated by their length (byte 2 of their ```tag``` value) and the first byte of the value (byte 3 of their ```tag``` value). Since the longest possible sequence of bytes is matched, when the buffer starts with all of ```022100```, ```payment_id``` wins over ```extra_nonce```.

If there is no match, the tag will be added to this table. The ```name``` of the new tag will be the Tx Extra Tag Id (```tx_extra_tag_id```) of the originating tag where the tag was first seen.

| Column | Description | Type | Constraint |
| - | - | - | - |
| ```tx_extra_tag_id``` | Identity | ```BIGSERIAL``` | ```PRIMARY KEY``` |
| ```name``` | Friendly name | ```VARCHAR``` | ```NOT NULL``` |
| ```tag``` | Binary value | ```BYTEA``` | ```NOT NULL``` |
| ```fixed_size``` | Fixed size | ```INTEGER``` | - |
| ```max_size``` | Maximum size | ```INTEGER``` | - |
| ```item_size``` | Item size | ```INTEGER``` | - |

### Default Data

| ```name``` | ```tag``` | ```fixed_size``` | ```max_size``` | ```item_size``` |  
| - | - | - | - | - |
| ```padding``` *(see Note 1)*| ```00``` | - | - | - |  
| ```pubkey``` | ```01``` | 32 | - | - |  
| ```extra_nonce``` | ```02``` | - | 255 *(see Note 2)* | - |  
| ```payment_id``` | ```022100``` *(see Note 3)* | 32 | - | - |  
| ```payment_id8``` | ```020901``` *(see Note 3)* | 8 | - | - |  
| ```merge_mining``` | ```03``` | - | - | - |  
| ```pubkey_additional``` | ```04``` | - | - | 32 *(see Note 4)* |  
| ```mysterious_minergate``` | ```DE``` | - | - | - |  

### Notes
1. **Padding tag**: CryptoNote Standard 005 [[1, page 2]](#References) specifies some rules for the padding tag (numbering ours): 

    ```
    a. padding is allowed only at the end of the Extra field  
    b. padding can only contain null bytes  
    c. the padding length is limited to 255 bytes  
    d. no explicit size is specified for padding (it occupies the remaining space of the Extra field)  
    ```

    We consider this rule set in two groups: (b) and (a,c,d).
    
    Regarding rule (b): suppose a padding tag contained non-null bytes, what could we do different? Because of rules (a) and (d), we know that we are at the end of the extra field and there cannot be any more tags, so we shouldn't try to parse the non-null bytes. It follows that there is nothing to do. Padding tag data written by this parser may contain non-null bytes.

    Regarding rules (a,c,d): rule (d) seems to override rules (a) and (c). If the data occupies the remaining space of the Extra field (d), then it is inherently true that padding is allowed only at the end of the Extra field (a): there will be no data left after. And, again, if the data occupies the remaining space of the Extra field (d), then the padding length is not limited to 255 bytes, it is limited to the remaining space of the Extra field. We could split padding tags by the 255 byte limit, but all we would gain is multiple records, so to analyze results for rule (c) we may as well simply query the length of the single padding tag record.

    Note that rule (c) appears in Monero as ```TX_EXTRA_PADDING_MAX_COUNT = 255``` in ```cryptonote_basic/tx_extra.h``` [[4]](#References).

    In all, these rules are more important to the "writer" side (the transaction author) of this field than to the "reader" (us/the parser).

    In "standard mode", this parser does the following when encountering a padding tag:
    1. Set the fixed size to the remaining size of the extra field (rule D).
    2. Record the padding tag.
    3. Since the entire extra field was consumed, parsing is concluded.

    The padding tag is implemented separately from the other tags. None of the size modifiers ```fixed_size, max_size, item_size``` can be used with it.

    An alternate parser behavior called "trim mode" is available for this tag. In this mode, instead of consuming the remaining size of the extra field, only consecutive null bytes are consumed (aka the front of the buffer is left trimmed by nulls) and recorded as the padding tag. The parser will then continue try to parse more tags from the non-null data occurring after the null bytes. The results may potentially be invalid since this situation breaks the padding tag rule (b); the validity of tag results in this case depends on the intention of the data, which only the creator of the transaction would know. To enable, set ```padding_tag_trim_mode = TRUE``` where it is defined in the variable declaration section in ```tx_extra_parse()```.

    As of block 2151099, there only two transactions on the blockchain which have a padding tag with non-null bytes: the coinbase transactions for blocks 2105609 and 2105566. The non-null bytes in these padding tags are not reasonably meaningful when parsed as tags. Therefore, since there is no existing use case for trim mode, standard mode is enabled by default.

2. **Extra nonce tag**: ```max_size``` is configured according to Monero core software: ```TX_EXTRA_NONCE_MAX_COUNT = 255``` from ```cryptonote_basic/tx_extra.h``` [[4]](#References).

3. Tags which include the size byte must specify ```fixed_size```. This is so the parser will next read the buffer into the Value field, not the Size field, as the size byte was already consumed from the buffer by the Tag. If bytes from the Value field are also included, ```fixed_size``` should equal the remaining number of bytes in the Value field, otherwise it should equal the size byte. For example, ```payment_id``` includes the size byte ```0x21 = 33```, then includes ```1``` byte from the Value field ```0x00```, so ```fixed_size = 33 - 1 = 32```.

4. **Item size column**: The ```pubkey_additional``` tag acts like an array, where the Size field is to be instead interpreted as the number of array items in the Value field, and the size of those items themselves is known by the parser instead of being present in the data. The parser will switch to this behavior when ```item_size``` is set.

5. Fixed size cannot be used with Item size or Maximum size. 

6. Item size and Maximum size can be used together.


## Table ```tx_extra_tag_list```
Tag ordering per transaction.

Tag ordering is a by-product of parsing the extra data.

Since the contents of the transaction extra data field are not verified [[1]](#References), tags may be added in any order. Like all metadata, this ordering is a fingerprint.

 It would also be possible to determine tag ordering through a query on ```tx_extra_data``` across a given transaction. Such a query would return an identical result to the data in this table.

The tag ordering data is recorded as a ```BYTEA``` column, ```tag_ordering```, which consists of only the tag bytes from the transaction's extra data, in their original order. Additionally, another copy is written as the Tag Ordering String, where some tags are disambiguated.


| Column | Description | Type | Constraint |
| - | - | - | - |
| ```tx_extra_tag_list_id``` | Identity | ```BIGSERIAL``` | ```PRIMARY KEY``` |
| ```block_height``` | Block height | ```BIGINT``` | - |
| ```tx_hash``` | Transaction hash | ```BYTEA``` | - |
| ```tx_is_coinbase``` | Transaction is coinbase *(see ```tx_extra_data```)* | ```BOOLEAN``` | - |
| ```tag_list``` | Tag list | ```BYTEA``` | ```NOT NULL``` |
| ```tag_list_string``` | Tag list string | ```BYTEA``` | ```NOT NULL``` |

### Tag List String
The Tag List String is equal to the Tag List with the following transpositions.

| Tag | Tag String | Description |
| - | - | - |
| ```payment_id8``` | ```20``` | Differentiate ```payment_id8``` from ```payment_id``` as they both use tag ```02``` |



### Indices
```tx_extra_schema_indices()``` includes the following indices for ```tx_extra_tag_list```.

- ```tx_extra_tag_list_block_height_idx```: index on ```{ block_height }```
- ```tx_extra_tag_list_tx_hash_idx```: index on ```{ tx_hash }```
- ```tx_extra_tag_list_tag_list_string_idx```: index on ```{ tag_list_string }```

---
# Procedure ```tx_extra_process()```
Iterates a transaction table in ranges, invoking ```tx_extra_parse()``` on the ```tx_extra``` data in each transaction.

```
CALL tx_extra_process(block_height_start, block_height_end, output_mode, coinbase_only);
```

## Parameters

| Parameter | Type | Description |
| - | - | - |
| ```block_height_start``` | ```INTEGER``` | Start block height |
| ```block_height_end``` | ```INTEGER``` | *Optional*: End block height |
| ```output_mode``` | ```INTEGER``` | *Optional*: See ["tx_extra_parse: Output Modes"](#Output_Modes). Defaults to ```NULL``` (Write mode). |
| ```coinbase_only``` | ```BOOLEAN``` | *Optional*: ```TRUE``` to process only coinbase transactions. Defaults to ```FALSE``` (both coinbase and user transactions).|

## Examples

```
-- Full sync
CALL tx_extra_process(1);

-- Debug the range 1220516-1220520
CALL tx_extra_process(1220516, 1220516, 1);
```


---
# Procedure ```tx_extra_test()```
Unit tests.

```
CALL tx_extra_test(test_id);
```

## Parameters

| Parameter | Type | Description |
| - | - | - |
| ```test_id``` | ```INTEGER``` | Test case to run. |

## `tx_extra_process` tests

| ```test_id``` | Description |
| - | - |
| 1 | Process 1 block in DEBUG mode |
| 2 | Process 1 block in WRITE mode |
| 3 | Process 2 blocks in DEBUG mode |
| 4 | Process 2 blocks COINBASE ONLY in DEBUG mode |

## `tx_extra_parse` tests
| ```test_id``` | Description |
| - | - |
| 5 | Common tags - Parse 0102 in DEBUG mode |
| 6 | Array tag - Parse 04 in DEBUG mode |
| 7 | Array tag - Parse known array tag with 0 size (see tx 02E4F925564EB9A6DC68D59A455A1AB8F67AA5A4B0027A7AC7BA2556E9342759) |
| 8 | Padding tag - Parse single padding tag case in DEBUG mode |
| 9 | Padding tag - Parse padding tag interrupted by valid tags in DEBUG mode |
| 10 | Padding tag - Parse padding tag interrupted by invalid tags in DEBUG mode |
| 11 | Padding tag - Parse known padding tag cases which include non-null bytes |
| 12 | Malformed tag - Remainder case T: see tx f6cff1edd1a7861ed13d494dd4ae7c4a7f42b5c3bf91457310d2166722c1316f) |
| 13 | Malformed tag - Remainder case TS |
| 14 | Malformed tag - Parse known item_size tag with invalid size (see tx E87C675A85F34ECAC58A8846613D25062F1813E1023C552B705AFAD32B972C38) |
| 15 | Size field - Test varint size decoding |

---
# Procedure ```tx_extra_schema()```
Creates tables and inserts known tag dataset.

```
CALL tx_extra_schema();
```


---
# Procedure ```tx_extra_schema_indices()```
Creates indices for tables.

```
CALL tx_extra_schema_indices();
```


---
# Materialized View `tx_extra_tag_count`
Count each tag present per transaction.

| Column | Description | Type |
| - | - | - |
| block_height | Block height | `BIGINT` |
| tx_hash | Transaction hash | `BYTEA` |
| n_padding | Number of tags: `padding` | `BIGINT` (per `COUNT`) |
| n_pubkey | Number of tags: `pubkey` | `BIGINT` (per `COUNT`) |
| n_extra_nonce | Number of tags: `extra_nonce` | `BIGINT` (per `COUNT`) |
| n_payment_id | Number of tags: `payment_id` | `BIGINT` (per `COUNT`) |
| n_payment_id8 | Number of tags: `payment_id8` | `BIGINT` (per `COUNT`) |
| n_merge_mining | Number of tags: `merge_mining` | `BIGINT` (per `COUNT`) |
| n_pubkey_additional | Number of tags: `pubkey_additional` | `BIGINT` (per `COUNT`) |
| n_mysterious_minergate | Number of tags of type: `mysterious_minergate` | `BIGINT` (per `COUNT`) |


---
# References

[1] CryptoNote Standard 005: CryptoNote Transaction Extra Field. [https://cryptonote.org/cns/cns005.txt](https://cryptonote.org/cns/cns005.txt)

[2] GitHub - Monero. [https://github.com/monero-project/monero](https://github.com/monero-project/monero) 

[3] Monero - secure, private, untraceable. [https://web.getmonero.org](https://web.getmonero.org)

[4] monero/tx_extra.h at master - monero-project/monero - GitHub. [https://github.com/monero-project/monero/blob/master/src/cryptonote_basic/tx_extra.h](https://github.com/monero-project/monero/blob/master/src/cryptonote_basic/tx_extra.h)

[5] GitHub - coinmetrics-io/haskell-tools: Tools for exporting blockchain data to analytical databases. [https://github.com/coinmetrics-io/haskell-tools](https://github.com/coinmetrics-io/haskell-tools)

## Results
See Monero tx_extra statistics report: [https://github.com/neptuneresearch/monero-tx-extra-statistics-report](https://github.com/neptuneresearch/monero-tx-extra-statistics-report)

Data obtained using this software was also featured in the following Monero Research Lab GitHub issues:

- Put extra field in the protocol: enforce sorted TLV format (with restricted tags) #61. [https://github.com/monero-project/research-lab/issues/61](https://github.com/monero-project/research-lab/issues/61)

- Transaction public key uniformity #71. [https://github.com/monero-project/research-lab/issues/71](https://github.com/monero-project/research-lab/issues/71)
