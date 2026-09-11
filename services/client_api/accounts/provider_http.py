"""Bounded public metadata reads without inherited client credentials or redirects."""
import json

import httpx


def unique_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate JSON field")
            result[key] = value
        return result
    def invalid_constant(_):
        raise ValueError("Non-finite JSON value")
    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid_constant)
    except RecursionError:
        raise ValueError("Excessive JSON nesting") from None


async def public_json(client: httpx.AsyncClient, url: str, limit: int = 65536):
    request = httpx.Request("GET", url, headers={"Accept": "application/json"},
        extensions={"timeout": {"connect": 8, "read": 8, "write": 8, "pool": 8}})
    response = await client.send(request, stream=True, follow_redirects=False, auth=None)
    try:
        if response.status_code != 200 or response.url != httpx.URL(url):
            raise ValueError("Invalid metadata response")
        body = bytearray()
        async for part in response.aiter_bytes():
            body.extend(part)
            if len(body) > limit:
                raise ValueError("Oversized metadata")
        return unique_json(body)
    finally:
        await response.aclose()
