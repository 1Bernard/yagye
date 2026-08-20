defmodule YagyeCore.Shared.Vault do
  @moduledoc false

  # AES-256-GCM envelope encryption for provider credentials.
  # Wire format: <<iv::12, tag::16, ciphertext::binary>>
  #
  # Key source: config :yagye_core, :credential_encryption_key (64-char hex = 32 bytes)
  # Rotate the key by re-encrypting all active credentials — the key is not per-row.
  # For production, replace key derivation with KMS-fetched data key.

  @aad "yagye_credential_v1"

  def encrypt(plaintext) when is_binary(plaintext) do
    key = encryption_key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)
    iv <> tag <> ciphertext
  end

  def decrypt(<<iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    key = encryption_key()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      :error -> {:error, :decryption_failed}
      plaintext -> {:ok, plaintext}
    end
  end

  def decrypt(_), do: {:error, :invalid_ciphertext}

  def encrypt_map(map) when is_map(map) do
    map |> Jason.encode!() |> encrypt()
  end

  def decrypt_map(binary) do
    with {:ok, json} <- decrypt(binary) do
      Jason.decode(json)
    end
  end

  defp encryption_key do
    :yagye_core
    |> Application.fetch_env!(:credential_encryption_key)
    |> Base.decode16!(case: :mixed)
  end
end
