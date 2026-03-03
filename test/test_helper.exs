ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Loomkin.Repo, :manual)

# Mox mock definitions for channel adapter tests
Mox.defmock(Loomkin.MockAdapter, for: Loomkin.Channels.Adapter)
Mox.defmock(Loomkin.MockTelegex, for: Loomkin.Channels.TelegexBehaviour)
Mox.defmock(Loomkin.MockNostrumApi, for: Loomkin.Channels.NostrumApiBehaviour)
