from __future__ import annotations

import argparse

from services.client_api.config import ClientAPISettings
from services.client_api.read_models import materialize_fixture_read_models


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Materialize development contract fixtures into the Client API read-model database."
    )
    parser.parse_args()
    settings = ClientAPISettings.from_environment()
    database_url = settings.read_model_database_url or settings.database_url
    counts = materialize_fixture_read_models(database_url, settings.fixture_root)
    for collection, count in counts.items():
        print(f"{collection}: {count}")


if __name__ == "__main__":
    main()
