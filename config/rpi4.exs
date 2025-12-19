import Config

# Configure VintageNet for a basic ethernet connection.
config :vintage_net, 
  regulatory_domain: "US",
  config: [
    {"usb0", %{type: VintageNet.Technology.Gadget, driver: VintageNet.Driver.Gadget.RNDIS}},
    {"eth0", %{type: VintageNet.Technology.Ethernet, ipv4: %{method: :dhcp}}},
    {"wlan0", %{type: VintageNet.Technology.WiFi, ipv4: %{method: :dhcp}}}
  ]

# Add any other target-specific configurations here.
