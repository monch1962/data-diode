# Data Diode

This repository contains an Elixir application simulating a unidirectional data diode proxy. It is designed to demonstrate a secure network architecture where data flows from an unsecured network (Service 1) to a secure network (Service 2) without any possibility of a reverse connection.

The entire application runs under a single Elixir supervisor, but the design cleanly separates the network-facing components (S1) from the secure components (S2), mimicking deployment on two sides of a physical data diode.

## 🤔 Why not just use a firewall?

While firewalls are essential components of network security, a data diode offers a fundamentally different and stronger guarantee of unidirectional data flow, particularly in high-security environments.

**Firewall:**

* **Function:** A firewall acts as a gatekeeper, inspecting network traffic and enforcing rules to permit or deny communication based on IP addresses, ports, protocols, and sometimes application-layer content.
* **Bidirectional by Design:** Firewalls are inherently bidirectional. They can be configured to allow traffic in one direction, but their underlying architecture is capable of two-way communication. This means there's always a theoretical (and sometimes practical) risk of misconfiguration, vulnerabilities, or advanced attacks that could bypass the rules and establish a reverse channel.
* **Software-based:** Most firewalls are software-based, running on general-purpose computing platforms, making them susceptible to software bugs, exploits, and complex attack vectors.

**Data Diode (Unidirectional Gateway):**

* **Function:** A data diode is a hardware-enforced security device that physically prevents data from flowing in more than one direction. It typically uses optical technology or specialized electronics to ensure that a return path for data is impossible.
* **Physical Unidirectionality:** Its core strength lies in its physical design. There is no electrical or optical path for data to travel back, making it immune to misconfiguration or software vulnerabilities that could create a reverse channel.
* **Use Cases:** Data diodes are used in environments where absolute assurance of one-way data flow is critical, such as:
  * **Critical Infrastructure (SCADA/ICS):** Protecting operational technology networks from external threats while allowing monitoring data out.
  * **Military and Government:** Ensuring classified networks remain isolated from less secure networks.
  * **Nuclear Facilities:** Preventing control signals from leaving a secure zone while allowing sensor data to be extracted.
  * **Industrial Control Systems:** Isolating control networks from enterprise networks.

**In summary:** While a firewall attempts to *manage* bidirectional traffic, a data diode *physically enforces* unidirectional traffic. For scenarios demanding the highest level of assurance against reverse data flow, a data diode provides a security guarantee that a firewall cannot. This Elixir application simulates the logical separation and one-way data flow that a physical data diode provides.

## 🛑 Architecture Overview

The system is split into two logical services connected by a simulated network path (UDP):

**1. Service 1 (S1): Unsecured Network Ingress (TCP to UDP)**
The function of Service 1 is to accept connections from potentially untrusted clients (e.g., IoT devices, legacy systems) and forward the data securely.

* **Ingress:** Listens for incoming connections on a TCP socket (LISTEN_PORT).

* **Encapsulation:** When data is received, it extracts the original TCP source IP address (4 bytes) and Port (2 bytes). This metadata is prepended to the original payload, creating a custom packet header.

* **Egress:** Forwards the newly encapsulated binary packet across the simulated security boundary using a UDP socket to Service 2.

**2. Service 2 (S2): Secured Network Egress (UDP to Storage)**
The function of Service 2 is to safely receive data from the unsecured side, verify the format, and write the contents to the secure system.

* **Ingress:** Listens for encapsulated data on a UDP socket (LISTEN_PORT_S2).

* **Decapsulation:** Parses the custom 6-byte header to recover the original source IP and Port.

* **Processing:** Logs the metadata and simulates writing the original payload to secure storage. Crucially, S2 never opens any TCP connection and does not send any data back.

## 🛠️ Project Setup

### Prerequisites

* Elixir (1.10+)

* Erlang/OTP (21+)

### Installation

Clone the repository:

```git clone [your-repo-link] data_diode```
```cd data_diode```

Install dependencies:

```mix deps.get```

## ⚙️ Configuration

The application uses environment variables for configuration.

| Variable | Service | Purpose | Default | Example |
| -------- | ------- | ------- | ------- | ------- |
| LISTEN_PORT | S1 TCP Listener | Port for incoming client TCP connections. | 8080 | 42000 |
| LISTEN_PORT_S2 | S2 UDP Listener | Port for internal UDP communication from S1. | 42001 | 42001 |

### Note on Service 1 Encapsulation

Service 1 (implemented in ```tcp_handler.ex``` and ```encapsulator.ex``` - which must be implemented to connect the services) is expected to send UDP packets to a specific target (e.g., ```127.0.0.1:LISTEN_PORT_S2```). If this target IP/Port is configurable, ensure you set it in your ```DataDiode.S1.Encapsulator``` module.

## ▶️ How to Run

### Development Mode (Debugging/Testing)

Use ```mix run --no-halt``` to keep the application running in your console.

``` # This starts both S1 on 42000 and S2 on 42001 (default)
LISTEN_PORT=42000 mix run --no-halt
```

### Production Mode (Deployment)

For reliable, production-ready deployment, generate an Elixir release.

#### Build the Release

```MIX_ENV=prod mix release```

This creates a tarball in ```_build/prod/rel/data_diode/releases/```.

#### Deploy and Run

Copy the release to your server, unpack it, and start the daemon:

```bash
### Replace path/to/release with the actual directory
cd path/to/release/data_diode

# Start the application in the background
LISTEN_PORT=42000 LISTEN_PORT_S2=42001 ./bin/data_diode start
```

Use ```./bin/data_diode stop``` to gracefully shut it down.

### Building for Nerves (Raspberry Pi)

This project can be built as a Nerves firmware for various embedded devices, including a wide range of Raspberry Pi models.

**Prerequisites:**

* [Install Nerves](https://hexdocs.pm/nerves/installation.html)

**Supported Raspberry Pi Models:**

To build for a specific Raspberry Pi model, you must use the correct `MIX_TARGET` environment variable and ensure the corresponding `nerves_system_*` dependency is included in your `mix.exs` file.

| Target Device | `MIX_TARGET` | Required Dependency in `mix.exs` |
| :--- | :--- | :--- |
| Raspberry Pi 5 | `rpi5` | `nerves_system_rpi5` |
| Raspberry Pi 4 | `rpi4` | `nerves_system_rpi4` |
| Raspberry Pi 3 (A+, B, B+), Zero 2 W | `rpi3a` | `nerves_system_rpi3a` |
| Raspberry Pi 2 | `rpi2` | `nerves_system_rpi2` |
| Raspberry Pi (A+, B, B+) | `rpi` | `nerves_system_rpi` |
| Raspberry Pi Zero, Zero W | `rpi0` | `nerves_system_rpi0` |

*Note: This project is pre-configured with `nerves_system_rpi4`. To target other models, you will need to add the appropriate dependency to the `nerves_deps/1` function in `mix.exs`.*

**Building the Firmware:**

1. **Set the Target:** Export the `MIX_TARGET` for your specific Raspberry Pi model. For example, for a Raspberry Pi 3 B+:

    ```bash
    export MIX_TARGET=rpi3a
    ```

2. **Install Dependencies:** Fetch the correct dependencies for your target.

    ```bash
    mix deps.get
    ```

3. **Build Firmware:** Create the firmware file.

    ```bash
    mix firmware
    ```

This will create a `.fw` file (e.g., `data_diode.fw`) in the `_build/<target>_dev/nerves/images/` directory. You can then burn this file to an SD card using the command `mix burn`.

## 🧪 Testing the Flow

Once the application is running:

Open a terminal/client and connect to Service 1 (TCP):

```bash
# Connect to S1's configured port (e.g., 42000)
nc localhost 42000
```

Type a message and hit enter (e.g., ```SENSOR_READING: 25.4```).

Check the logs where the Elixir application is running:

* S1 will log that it received the data and forwarded a UDP packet.

* S2 will immediately log that it received, decapsulated, and simulated the secure write:

```txt

[info] S2: Decapsulated packet from 127.0.0.1:45321. Payload size: 21 bytes.
[debug] S2: Successfully wrote 21 bytes to data_... (Simulated secure write)
```

*Note: The IP/Port logged by S2 will be the temporary source of the TCP client connecting to S1.*

## 📊 Confirming OpenTelemetry Traces

This application is instrumented with OpenTelemetry. To confirm that trace data is being generated and exported, you need to run an OpenTelemetry Collector. The collector will receive the traces from your application and can then process, store, or forward them.

A simple way to test this is to run a collector that prints all received traces to its standard output.

**Steps:**

1. **Start the OpenTelemetry Collector** in a *separate terminal window*.

    ```bash
    docker run --rm -it -p 4317:4317 -p 4318:4318 -p 8888:8888 -p 55680:55680 otel/opentelemetry-collector-contrib:latest --config=- <<EOF
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:
      batch:
    exporters:
      logging:
        verbosity: detailed
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
    EOF
    ```

    *This command exposes the necessary OTLP ports (4317 for gRPC, 4318 for HTTP) and configures the collector to print all received telemetry data to its standard output.*

2. **Start your Elixir application** (as described in "How to Run" section).
3. **Send some data** through your application (e.g., using `nc localhost 42000`).
4. **Observe the terminal where the collector is running.** You should see detailed logs of the traces generated by your Elixir application, confirming that OpenTelemetry data is being exported.

## 🗃️ Key Files

| Filepath | Description |
| --- | --- |
| ```lib/data_diode/application.ex``` | Supervisor: Defines and starts the S1 and S2 listeners. |
| ```lib/data_diode/s1/listener.ex``` | Service 1: TCP Listener. Accepts client connections and starts a handler for each.|
| ```lib/data_diode/s1/tcp_handler.ex``` | Service 1: Handles an individual TCP stream, extracts metadata, and calls the Encapsulator. |
| ```lib/data_diode/s2/listener.ex``` | Service 2: UDP Listener. Receives packets from S1 and passes them to the Decapsulator.|
| ```lib/data_diode/s2/decapsulator.ex``` | Service 2: Core security logic. Parses the custom header and simulates the final secure write. |
| ```mix.exs``` | Project configuration, dependencies, and release definition. |
