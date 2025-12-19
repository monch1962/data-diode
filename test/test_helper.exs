ExUnit.start()

# Start the Mox application supervisor before any tests run
Application.ensure_all_started(:mox)

Mox.defmock(DataDiode.S2.DecapsulatorMock, for: DataDiode.S2.Decapsulator)
Mox.defmock(DataDiode.S1.EncapsulatorMock, for: DataDiode.S1.Encapsulator)
