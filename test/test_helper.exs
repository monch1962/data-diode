ExUnit.start()

# Start the Mox application supervisor before any tests run
Application.ensure_all_started(:mox)

Mox.defmock(DataDiode.S2.DecapsulatorMock, for: DataDiode.S2.Decapsulator)
Mox.defmock(DataDiode.S1.EncapsulatorMock, for: DataDiode.S1.Encapsulator)

# Load test support modules
Code.require_file("test/support/missing_hardware.ex")
Code.require_file("test/support/hardware_fixtures.ex")

