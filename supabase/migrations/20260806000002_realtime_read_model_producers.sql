alter table if exists client_read_model_document
    add column if not exists producer varchar(64);

create index if not exists ix_client_read_model_document_producer
    on client_read_model_document (producer);
