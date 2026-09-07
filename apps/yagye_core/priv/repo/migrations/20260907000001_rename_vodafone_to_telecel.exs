defmodule YagyeCore.Repo.Migrations.RenameVodafoneToTelecel do
  use Ecto.Migration

  def up do
    # Ghana's Vodafone rebranded to Telecel in 2024. The simulator uses TELECEL
    # throughout; Core's seed had the old name, causing name_enquiry rejections.
    execute """
    UPDATE momo_network_config
    SET network = 'TELECEL', display_name = 'Telecel Cash'
    WHERE network = 'VODAFONE'
    """
  end

  def down do
    execute """
    UPDATE momo_network_config
    SET network = 'VODAFONE', display_name = 'Vodafone Cash'
    WHERE network = 'TELECEL'
    """
  end
end
