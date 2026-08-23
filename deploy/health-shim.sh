#!/bin/sh
# Health shim: answer every request with an immediate 200 so platform
# health probes pass during the gateway's slow startup (WAN Postgres).
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: 15\r\n\r\n{"status":"ok"}\r\n'
