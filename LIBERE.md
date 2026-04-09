# Libere Chatwoot Fork

Fork of [Chatwoot](https://github.com/chatwoot/chatwoot) with Libere-specific patches. We maintain a `libere-v<version>` branch that rebases our patches on top of each upstream release.

## Patches

### 1. Per-inbox email domain and sender (mailer customization)

**Env vars**: `MAILER_INBOUND_INBOX_PREFERENCE`, `MAILER_SENDER_INBOX_PREFERENCE`

Allows configuring different inbound/sender email domains per inbox instead of using a single account-wide domain. When `MAILER_INBOUND_INBOX_PREFERENCE=true`, the inbox channel's email domain takes priority over `MAILER_INBOUND_EMAIL_DOMAIN`. When `MAILER_SENDER_INBOX_PREFERENCE=true`, the inbox email address is used as the sender instead of the account `support_email`.

**Files modified**:
- `app/mailers/conversation_reply_mailer.rb`
- `app/mailers/conversation_reply_mailer_helper.rb`
- `app/models/channel/email.rb`
- `.env.example`
- `spec/mailers/conversation_reply_mailer_spec.rb`

### 2. Booking.com chat grouping

Groups incoming Booking.com chat emails into the same conversation by extracting a reservation ID from the sender address pattern `<id>-*@mchat.booking.com`.

**Files modified**:
- `app/services/mailbox/conversation_finder_strategies/new_conversation_strategy.rb`

### 3. Airbnb chat grouping

Groups incoming Airbnb messages into the same conversation by combining the sender name and subject, since Airbnb rotates the reply-to email address on each message.

**Files modified**:
- `app/services/mailbox/conversation_finder_strategies/new_conversation_strategy.rb`

### 4. Dockerfile for building from public image

Builds a custom image on top of the official `chatwoot/chatwoot` image, copying only the patched `app/` directory, `config/application.rb`, and `Gemfile`/`Gemfile.lock`.

**Files modified**:
- `Dockerfile`

## Update Procedure

### Prerequisites

```bash
git clone https://github.com/liberetech/chatwoot.git
cd chatwoot
git remote add upstream https://github.com/chatwoot/chatwoot.git
```

### Steps

1. **Sync master and tags**

    ```bash
    git checkout master
    git pull upstream master
    git fetch upstream --tags
    git push origin master --tags --no-verify
    ```

2. **Create new libere branch by rebasing patches onto the new version**

    ```bash
    git checkout libere-v<current>    # e.g. libere-v4.11.1
    git checkout -b libere-v<new>     # e.g. libere-v4.12.1
    git rebase upstream/v<new>        # e.g. upstream/v4.12.1
    ```

    Resolve any conflicts during rebase. The patches are small so conflicts are typically straightforward.

3. **Update Dockerfile base image**

    ```bash
    # Edit Dockerfile: update FROM tag to the new version
    git add Dockerfile
    git commit -m "Updated dockerfile from version"
    ```

4. **Push and build**

    ```bash
    git push origin libere-v<new>
    docker build . --tag eu.gcr.io/air-build/chatwoot:v<new>-libere.1
    docker push eu.gcr.io/air-build/chatwoot:v<new>-libere.1
    ```

    Push requires `air-build/roles/artifactregistry.writer` permission.