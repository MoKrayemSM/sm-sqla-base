# sm-sqla-base

The **single source of the SQL Anywhere 17 client runtime** for every SoftMind
Node service that talks to the legacy SQLA database.

Today each service re-implements an identical `sqla-installer` Docker stage that
extracts the same 66 MB proprietary tarball, runs the same silent `setup`, and
prunes to the same `lib64` + `res`. Six copies of the same 68 MB layer, six
build contexts each carrying the tarball. This image collapses that into **one**.

## What it contains (and what it deliberately does not)

It owns exactly one thing: the extracted, pruned client at
`/opt/sqlanywhere17` — `lib64/` (driver `.so` files) and `res/` (charset/error
message files).

It intentionally does **not** include Node, a build toolchain, the `sqlanywhere`
npm binding, or unixODBC, because consumers diverge in how they use SQLA:

| Consumer | Mechanism | Needs |
|---|---|---|
| smAdm, smNode, smsys, smLogin, smPublicApis | `sqlanywhere` npm **native binding** (node-gyp vs. `SQLANY17`) | `git`, node-gyp, `bin64` on `PATH` |
| **SmAttachments** (sm-aws) | **unixODBC** + `/etc/odbcinst.ini` → `libdbodbc17_r.so` (no `sqlanywhere` dep) | `unixodbc`, odbcinst |

A fat base would force one path onto a consumer that uses the other. So the base
stays lean and each service layers its own mechanism on top.

## How consumers use it

In each service's Dockerfile, delete the local `sqla-installer` stage and
replace the copy line with:

```dockerfile
COPY --from=sm-sqla-base:17-bookworm /opt/sqlanywhere17 /opt/sqlanywhere17
```

(Under Jenkins/Harbor this becomes `--from=<registry>/sm-sqla-base:17-bookworm`.)
Everything downstream — `SQLANY17`, `LD_LIBRARY_PATH`, the node-gyp build or the
ODBC registration — stays in the consumer Dockerfile, unchanged.

## The tarball (not committed)

`sqla17_client_linux_x86x64.tar.gz` is proprietary and **gitignored**. Obtain it
from the internal artifact store and drop it in this directory before building.
`make check` verifies it is present.

## Build & verify

```bash
make check     # tarball present and checksum matches
make build     # builds sm-sqla-base:17-bookworm
make verify    # runs the image; lists /opt/sqlanywhere17 (lib64, res)
make shell     # poke around interactively
```

The build itself fails fast if `lib64/libdbodbc17_r.so` or `res/` is missing, or
if the driver has unresolved shared-lib dependencies.

## Migration order

1. Build & push `sm-sqla-base:17-bookworm` (this repo).
2. Repoint all 6 service Dockerfiles to `COPY --from` it; rebuild each to confirm
   parity (the 5 binding apps + SmAttachments' ODBC path).
3. Drop the now-redundant tarball copies from the other build contexts.
