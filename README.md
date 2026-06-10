# MongoDB Edition Diagnostic

This repository contains a small read-only shell script that helps identify whether a MongoDB installation appears to be MongoDB Community or MongoDB Enterprise.

The script is intended for customers to run on their own host and paste the output back to support.

## Script

- `identify_mongodb_edition.sh`

## What It Checks

The script looks for MongoDB edition indicators from:

- Local `mongod --version` output
- Local `mongos --version` output
- Installed packages from `dpkg`, `rpm`, or `brew`
- Running `mongod` or `mongos` processes
- Optional `mongosh` `buildInfo` output when a MongoDB URI is provided

It does not change MongoDB configuration, write to the database, restart services, or collect database contents.

## Customer Instructions

Download or copy the script to the MongoDB host, then run:

```bash
chmod +x identify_mongodb_edition.sh
./identify_mongodb_edition.sh
```

If the customer can safely connect with `mongosh`, they can provide a MongoDB URI:

```bash
./identify_mongodb_edition.sh --uri mongodb://localhost:27017
```

If authentication is required, do not include credentials unless your support process explicitly allows it.

## Output

The script prints:

- Host and timestamp information
- Evidence found from each check
- A final verdict:
  - `MongoDB Community indicators were found`
  - `MongoDB Enterprise indicators were found`
  - `Inconclusive`

Customers should paste the full output back to support.

## Exit Codes

- `0`: Community indicators found
- `2`: Enterprise indicators found
- `3`: Inconclusive
- `1`: Invalid script usage

