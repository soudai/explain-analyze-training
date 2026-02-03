create table demo.shop
(
    id   integer not null
        constraint shop_pk
            primary key,
    name integer
);

alter table demo.shop
    owner to "pg-demo18";

create table demo.item
(
    id      integer not null
        constraint item_pk
            primary key,
    shop_id integer
        constraint item_shop_id_fk
            references demo.shop,
    constraint item_pk_2
        unique (id, shop_id)
);

alter table demo.item
    owner to "pg-demo18";

create table demo."order"
(
    id      integer not null,
    item_id integer not null
        constraint order_item_id_fk
            references demo.item,
    constraint order_pk
        primary key (id, item_id)
);

alter table demo."order"
    owner to "pg-demo18";

create table demo.shop_order
(
    id      integer not null,
    shop_id integer not null
        constraint shop_order_shop_id_fk
            references demo.shop,
    constraint shop_order_pk
        primary key (id, shop_id)
);

alter table demo.shop_order
    owner to "pg-demo18";

create table demo.shop_order_detail
(
    order_id integer not null,
    shop_id  integer not null,
    item_id  integer not null,
    constraint shop_order_detail_pk
        primary key (order_id, shop_id, item_id),
    constraint shop_order_detail_shop_order_id_shop_id_fk
        foreign key (order_id, shop_id) references demo.shop_order,
    constraint shop_order_detail_item_id_shop_id_fk
        foreign key (item_id, shop_id) references demo.item (id, shop_id)
);

alter table demo.shop_order_detail
    owner to "pg-demo18";

create index shop_order_detail_item_id_index
    on demo.shop_order_detail (item_id);

