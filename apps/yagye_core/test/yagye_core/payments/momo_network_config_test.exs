defmodule YagyeCore.Payments.MomoNetworkConfigTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Payments.Schemas.MomoNetworkConfig
  alias YagyeCore.Repo

  describe "seeded data" do
    test "MTN config exists" do
      config = Repo.get(MomoNetworkConfig, "MTN")
      assert config != nil
      assert config.display_name == "MTN Mobile Money"
      assert config.callback_reliability == "primary"
      assert config.supports_name_enquiry == true
      assert config.supports_reversal == true
      assert "024" in config.msisdn_prefixes
    end

    test "VODAFONE config exists" do
      config = Repo.get(MomoNetworkConfig, "VODAFONE")
      assert config != nil
      assert config.callback_reliability == "advisory"
      assert config.supports_name_enquiry == false
    end

    test "AIRTELTIGO config exists" do
      config = Repo.get(MomoNetworkConfig, "AIRTELTIGO")
      assert config != nil
      assert "026" in config.msisdn_prefixes
    end
  end

  describe "changeset/2" do
    test "valid changeset" do
      attrs = %{
        network: "TEST_NET",
        display_name: "Test Network",
        msisdn_prefixes: ["099"],
        prompt_timeout_seconds: 60,
        callback_reliability: "primary",
        poll_interval_seconds: 5,
        supports_name_enquiry: false,
        supports_reversal: false
      }

      changeset = MomoNetworkConfig.changeset(%MomoNetworkConfig{}, attrs)
      assert changeset.valid?
    end

    test "rejects invalid callback_reliability" do
      changeset =
        MomoNetworkConfig.changeset(%MomoNetworkConfig{}, %{
          network: "X",
          display_name: "X",
          msisdn_prefixes: ["099"],
          prompt_timeout_seconds: 60,
          callback_reliability: "eventual",
          poll_interval_seconds: 5
        })

      assert "is invalid" in errors_on(changeset).callback_reliability
    end

    test "rejects zero prompt_timeout_seconds" do
      changeset =
        MomoNetworkConfig.changeset(%MomoNetworkConfig{}, %{
          network: "X",
          display_name: "X",
          msisdn_prefixes: ["099"],
          prompt_timeout_seconds: 0,
          callback_reliability: "primary",
          poll_interval_seconds: 5
        })

      assert "must be greater than 0" in errors_on(changeset).prompt_timeout_seconds
    end
  end
end
