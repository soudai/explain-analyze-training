create table public.trump
(
    id         bigserial
        constraint trump_pk
            primary key,
    created_at timestamp default now() not null
);

alter table public.trump
    owner to "pg-demo17";

create table public.card
(
    id       bigserial
        constraint card_pk
            primary key,
    trump_id bigint  not null
        constraint card_trump_id_fk
            references public.trump,
    type     text    not null,
    number   integer not null,
    constraint card_unique_key
        unique (trump_id, type, number)
);

alter table public.card
    owner to "pg-demo17";

-- https://wasm.supabase.com/ 利用時には以下のDDLを利用する

create table trump
(
    id         bigserial
        constraint trump_pk
            primary key,
    created_at timestamp default now() not null
);

create table card
(
    id       bigserial
        constraint card_pk
            primary key,
    trump_id bigint  not null
        constraint card_trump_id_fk
            references trump,
    type     text    not null,
    number   integer not null,
    constraint card_unique_key
        unique (trump_id, type, number)
);

