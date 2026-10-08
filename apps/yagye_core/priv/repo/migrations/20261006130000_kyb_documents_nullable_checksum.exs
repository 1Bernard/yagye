defmodule YagyeCore.Repo.Migrations.KybDocumentsNullableChecksum do
  use Ecto.Migration

  def change do
    # In the presigned-URL upload flow (P21), a document row is created with
    # status=pending_upload before the file is uploaded. The checksum is only
    # known after the client completes the S3 PUT and calls confirm-upload.
    alter table(:kyb_documents) do
      modify :checksum, :text, null: true
    end
  end
end
