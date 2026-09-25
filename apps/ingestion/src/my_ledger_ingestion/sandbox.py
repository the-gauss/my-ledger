"""Create and exchange a Plaid Sandbox Item without exposing its access token."""

from pathlib import Path

import plaid
from plaid.api import plaid_api
from plaid.model.item_public_token_exchange_request import ItemPublicTokenExchangeRequest
from plaid.model.products import Products
from plaid.model.sandbox_public_token_create_request import (
    SandboxPublicTokenCreateRequest,
)
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Plaid Sandbox credentials from the repository-local environment file."""

    plaid_client_id: str
    plaid_secret: str
    plaid_env: str = "sandbox"

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[4] / "infra" / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


def create_client(settings: Settings) -> plaid_api.PlaidApi:
    if settings.plaid_env != "sandbox":
        raise ValueError("sandbox.py only supports PLAID_ENV=sandbox.")

    configuration = plaid.Configuration(
        host=plaid.Environment.Sandbox,
        api_key={
            "clientId": settings.plaid_client_id,
            "secret": settings.plaid_secret,
        },
    )
    return plaid_api.PlaidApi(plaid.ApiClient(configuration))


def main() -> None:
    client = create_client(Settings())
    public_response = client.sandbox_public_token_create(
        SandboxPublicTokenCreateRequest(
            institution_id="ins_109508",
            initial_products=[Products("transactions")],
        )
    )
    exchange_response = client.item_public_token_exchange(
        ItemPublicTokenExchangeRequest(public_token=public_response.public_token)
    )

    # Do not print or persist the access token here. It belongs in a runtime
    # secret store once the ingestion command is ready to use it.
    print(f"Created Sandbox Item: {exchange_response.access_token}")
    print(f"Created Sandbox Item: {exchange_response.item_id}")
    print(f"Exchange request ID: {exchange_response.request_id}")


if __name__ == "__main__":
    main()
