# ローカル Docker 環境 構築手順

**概要**
- Postgres と MySQL を `docker-compose` で起動します。
- 管理用のターゲットは [docker/Makefile](docker/Makefile) に定義されています。

**前提条件**
- Windows + WSL2（Ubuntu 24.04）
- Docker Desktop（WSL2 統合を有効化）
- Docker Compose v2（Docker Desktop 同梱）

**構成の要点**
- Postgres: 画像 `postgres:18`、コンテナ名 `pg-demo18`、DB `pgdemo`
- MySQL: 画像 `mysql:8.4`、コンテナ名 `my-demo84`
- 名前付きボリューム: `pg-demo-data`、`my-demo-data`（データ永続化）

**セキュリティ注意**
- Postgres の初期パスワードは compose で `pg!!!` に設定済みです（開発用途の想定）。必要に応じて変更してください。
- 既にボリュームが存在する場合は、環境変数を変更しても既存クラスターのパスワードは変わりません。新しいパスワードを反映するには以下のいずれかが必要です。
	- `make clean` でボリュームを削除して再初期化する
	- `ALTER USER "pg-demo18" WITH PASSWORD '新パスワード';` を実行する

**Makefile の注意点**
- `run` は `pull -> up -> logs` を順に実行します。
	- `pull` は `git pull origin main` を実行します。ローカル変更がある場合はコンフリクトに注意してください（必要ならコミット/スタッシュ）。
- `pg-bash` は Compose の `pg-demo18` を参照するように修正済みです。
	- Postgres のシェルは `make pg-bash` を使用できます。
	- MySQL の `my-bash` もそのまま利用できます。
 - DB クライアント用ターゲット: `psql`（Postgres）、`mysql`（MySQL）を用意しています。

**起動手順**
1. WSL 上でワークスペースに移動します。

```bash
cd explain-analyze-training/docker
```

2.（推奨）ワンコマンドで最新化・起動・ログ確認まで実行します。

```bash
make run
```

— または —

2'. コンテナをバックグラウンドで起動します。

```bash
make up
```

3'. 起動ログを追跡します（状態確認）。

```bash
make logs
```

4. 稼働中コンテナを確認します。

```bash
docker compose ps
```

ポート割り当て:
- Postgres: ホスト `5432`
- MySQL: ホスト `3306`

**動作確認（DB に接続）**

- Postgres（Makefile の `psql` を使用）

```bash
make psql
```

- MySQL（Makefile の `mysql` を使用。root パスワードは compose の `MYSQL_ROOT_PASSWORD` 設定値）

```bash
make mysql
# プロンプトが出たら、例: root!!! を入力
```

**停止・削除**
- コンテナ停止

```bash
make down
```

- コンテナとボリュームを削除（データも削除されます）

```bash
make clean
```

**シェルアクセス**
- MySQL コンテナ

```bash
make my-bash
```

 - Postgres コンテナ

```bash
make pg-bash
```

補足（直接実行の代替コマンド）
- Postgres: `docker exec -it pg-demo18 psql -U pg-demo18 -d pgdemo`
- MySQL: `docker exec -it my-demo84 mysql -uroot -p`

**トラブルシュート**
- Postgres が起動直後に終了する:
	- 既存のデータディレクトリと環境変数の不整合が原因のことがあります。必要に応じて `make clean` 後に再起動してください。
- `make run` が失敗する:
	- `git pull origin main` でコンフリクトが発生している可能性があります。手動で解消したうえで `make up` を実行してください。
- ポート競合（5432/3306 が使用中）:
	- 既存の DB がホストで動いていないか確認し、必要なら停止してください。

