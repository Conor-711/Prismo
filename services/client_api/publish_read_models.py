from __future__ import annotations

import argparse
import os
from pathlib import Path

from services.client_api.config import ClientAPISettings
from services.client_api.read_models import ReadModelPublisher, load_read_model_directory


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Publish and atomically activate a complete bSmart client read model snapshot."
    )
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--source-version", required=True)
    parser.add_argument("--schema-version", default="1.3.0")
    parser.add_argument("--channel", default="production")
    arguments = parser.parse_args()
    input_dir = arguments.input_dir.resolve()
    if not input_dir.is_dir():
        parser.error(f"input directory does not exist: {input_dir}")
    if not arguments.source_version.strip():
        parser.error("--source-version must not be empty")

    settings = ClientAPISettings.from_environment()
    database_url = os.environ.get(
        "BSMART_READ_MODEL_DATABASE_URL",
        settings.read_model_database_url or settings.database_url,
    )
    publisher = ReadModelPublisher(database_url, channel=arguments.channel)
    try:
        result = publisher.publish(
            load_read_model_directory(input_dir),
            source_version=arguments.source_version.strip(),
            schema_version=arguments.schema_version,
        )
    finally:
        publisher.dispose()

    print(f"release_id: {result.release_id}")
    print(f"documents: {result.document_count}")
    print(f"existing: {str(result.existing).lower()}")
    for collection, count in result.counts.items():
        print(f"{collection}: {count}")


if __name__ == "__main__":
    main()
