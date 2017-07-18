defmodule Cicada.DeviceManager.Device.SmartMeter.Neurio do
  use Cicada.DeviceManager.DeviceHistogram
  require Logger
  alias Cicada.{DeviceManager}
  @behaviour DeviceManager.Behaviour.SmartMeter

  def start_link(id, device) do
    GenServer.start_link(__MODULE__, {id, device}, name: id)
  end

  def demand(pid) do
    GenServer.call(pid, :demand)
  end

  def produced(pid) do
    GenServer.call(pid, :produced)
  end

  def consumed(pid) do
    GenServer.call(pid, :consumed)
  end

  def price(pid) do
    GenServer.call(pid, :consumed)
  end

  def device(pid) do
    GenServer.call(pid, :device)
  end

  def update_state(pid, state) do
    GenServer.call(pid, {:update, state})
  end

  def get_id(device) do
    mac = device |> Map.get(:meter_mac_id)
    :"Neurio-#{mac}"
  end

  def map_state(%Neurio.State{} = state) do
    %DeviceManager.Device.SmartMeter.State{
      connection_status: state.connection_status,
      meter_mac_id: state.meter_mac_id,
      price: state.price,
      signal: state.signal,
      meter_type: state.meter_type,
      kw_delivered: state.kw_delivered,
      kw_received: state.kw_received,
      channel: "1",
      kw: state.kw
    }
  end

  def init({id, device}) do
    {:ok, %DeviceManager.Device{
      module: Neurio,
      type: :smart_meter,
      device_pid: :"#{device.meter_mac_id}",
      interface_pid: id,
      name: "Neurio - #{device.meter_mac_id}",
      state: device |> map_state
    }}
  end

  def handle_call({:update, state}, _from, device) do
    state = state |> map_state
    {:reply, state, %DeviceManager.Device{device | state: state}}
  end

  def handle_call(:device, _from, device) do
    {:reply, device, device}
  end

  def handle_call(:demand, _from, device) do
    {:reply, device.kw_received, device}
  end

  def handle_call(:produced, _from, device) do
    {:reply, device.kw_received, device}
  end

  def handle_call(:consumed, _from, device) do
    {:reply, device.kw_delivered, device}
  end

  def handle_call(:price, _from, device) do
    {:reply, device.price, device}
  end

end

defmodule Cicada.DeviceManager.Discovery.SmartMeter.Neurio do
  alias Cicada.DeviceManager.Device.SmartMeter
  alias Cicada.NetworkManager
  alias Cicada.NetworkManager.State, as: NM
  use Cicada.DeviceManager.Discovery, module: SmartMeter.Neurio
  require Logger

  @url System.get_env("NEURIO_URL")

  defmodule State do
    defstruct started: false
  end

  def register_callbacks do
    Logger.info "Starting Neurio"
    NetworkManager.register
    case NetworkManager.up do
      true ->
        get_url()
        %State{started: true}
      false -> %State{}
    end
  end

  def get_url do
    case @url do
      "" -> nil
      nil -> nil
      address ->
        Logger.info "Neurio starting at IP: #{address}"
        Process.send_after(self(), {:get, address}, 1000)
    end
  end

  def handle_info(%NM{bound: true}, %State{started: false} = state) do
    get_url()
    {:noreply, %State{state | started: true}}
  end

  def handle_info(%NM{}, state), do: {:noreply, state}

  def handle_info({:get, address}, state) do
    state =
      case address |> Neurio.get([], [recv_timeout: 700, timeout: 1300]) do
        {:ok, %HTTPoison.Response{} = res} ->
          case res |> Map.get(:body) do
            nil -> state
            body -> handle_device(state)
          end
        {:error, %HTTPoison.Error{} = err} ->
          Logger.info "Neurio Client Error: #{err.reason}"
          state
      end
    Process.send_after(self(), {:get, address}, 2300)
    {:noreply, state}
  end

  def handle_info(_device, state) do
    {:noreply, state}
  end

end
