ExUnit.start()

# Start the Mox application supervisor before any tests run
Application.ensure_all_started(:mox)
