defmodule DataDiode.ConfigValidatorTest do
  use ExUnit.Case, async: false
  alias DataDiode.ConfigValidator

  describe "validate!/0" do
    test "validates successfully with valid configuration" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert :ok = ConfigValidator.validate!()
    end

    test "raises error with invalid s1_port" do
      Application.put_env(:data_diode, :s1_port, -1)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid port/, fn ->
        ConfigValidator.validate!()
      end
    end

    test "raises error with port too large" do
      Application.put_env(:data_diode, :s1_port, 99_999)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid port/, fn ->
        ConfigValidator.validate!()
      end
    end

    test "raises error with invalid port type" do
      Application.put_env(:data_diode, :s1_port, "not_a_number")
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid port/, fn ->
        ConfigValidator.validate!()
      end
    end

    test "raises error with invalid s2_port" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 70_000)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid port/, fn ->
        ConfigValidator.validate!()
      end
    end

    test "validates successfully with nil s1_udp_port" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :s1_udp_port, nil)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert :ok = ConfigValidator.validate!()
    end

    test "validates successfully with valid s1_udp_port" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :s1_udp_port, 161)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert :ok = ConfigValidator.validate!()
    end

    test "raises error with invalid s1_ip" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :s1_ip, "999.999.999.999")
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid IP address/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :s1_ip)
    end

    test "raises error with invalid s2_ip" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :s2_ip, "not_an_ip")
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      assert_raise ArgumentError, ~r/Invalid IP address/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :s2_ip)
    end

    test "creates data directory if it doesn't exist" do
      test_dir = System.tmp_dir!() <> "/data_diode_test_#{System.unique_integer()}"

      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, test_dir)
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      try do
        assert :ok = ConfigValidator.validate!()
        assert File.dir?(test_dir)
      after
        File.rm_rf(test_dir)
        Application.delete_env(:data_diode, :data_dir)
      end
    end

    test "raises error when data_dir cannot be created" do
      # Use a path that can't be created
      invalid_dir = "/root/no_permission_#{System.unique_integer()}"

      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, invalid_dir)
      Application.put_env(:data_diode, :allowed_protocols, [:any])

      # Note: This test might fail if run as root
      if System.get_env("USER") not in ["root", nil] do
        assert_raise ArgumentError, ~r/Cannot create data directory/, fn ->
          ConfigValidator.validate!()
        end
      end
    after
      Application.delete_env(:data_diode, :data_dir)
    end

    test "raises error with invalid allowed_protocols type" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, "not_a_list")

      assert_raise ArgumentError, ~r/Invalid allowed_protocols/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :allowed_protocols)
    end

    test "raises error with invalid protocol values" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:modbus, "not_an_atom"])

      assert_raise ArgumentError, ~r/Invalid protocol values/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :allowed_protocols)
    end

    test "raises error with invalid rate_limit" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])
      Application.put_env(:data_diode, :max_packets_per_sec, -1)

      assert_raise ArgumentError, ~r/Invalid max_packets_per_sec/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :max_packets_per_sec)
    end

    test "raises error with invalid disk_cleaner_interval" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])
      Application.put_env(:data_diode, :disk_cleaner_interval, 0)

      assert_raise ArgumentError, ~r/Invalid disk_cleaner_interval/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :disk_cleaner_interval)
    end

    test "raises error with invalid disk_cleanup_batch_size" do
      Application.put_env(:data_diode, :s1_port, 8080)
      Application.put_env(:data_diode, :s2_port, 42_001)
      Application.put_env(:data_diode, :data_dir, ".")
      Application.put_env(:data_diode, :allowed_protocols, [:any])
      Application.put_env(:data_diode, :disk_cleanup_batch_size, -10)

      assert_raise ArgumentError, ~r/Invalid disk_cleanup_batch_size/, fn ->
        ConfigValidator.validate!()
      end
    after
      Application.delete_env(:data_diode, :disk_cleanup_batch_size)
    end
  end
end
