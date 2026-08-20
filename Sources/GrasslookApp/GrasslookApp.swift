import SwiftUI
import AppKit

@main
struct GrasslookApp: App {
    @StateObject private var coordinator = GrasslookCoordinator()

    var body: some Scene {
        MenuBarExtra {
            GrasslookMenuContent(coordinator: coordinator)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                Text(menuBarTitle)
                    .font(.caption.monospacedDigit())
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                scheduler: coordinator.scheduler,
                interception: coordinator.interception,
                analytics: coordinator.analytics,
                audio: coordinator.audio
            )
        }
    }

    private var menuBarTitle: String {
        switch coordinator.scheduler.state {
        case .inBreak:
            return "Break"
        case .paused:
            return "Paused"
        case .countingDown(let remaining, _):
            let mins = Int(ceil(remaining / 60.0))
            return "\(mins)m"
        default:
            return "Active"
        }
    }
}

struct GrasslookMenuContent: View {
    @ObservedObject var coordinator: GrasslookCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.title3)
                    .foregroundStyle(ForestTheme.sage)
                Text("Grasslook")
                    .font(.headline.weight(.semibold))
                Spacer()
                statusBadge
            }

            Divider()

            // Countdown Status Cards
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(ForestTheme.sage)
                        .frame(width: 18, alignment: .center)
                    Text("Next Micro-Break:")
                        .font(.subheadline)
                    Spacer()
                    Text(formattedMinutes(coordinator.scheduler.secondsUntilNextMicro))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ForestTheme.leaf)
                }

                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(ForestTheme.foliage)
                        .frame(width: 18, alignment: .center)
                    Text("Next Long Break:")
                        .font(.subheadline)
                    Spacer()
                    Text(formattedMinutes(coordinator.scheduler.secondsUntilNextLong))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ForestTheme.leaf)
                }
            }

            Divider()

            // Quick Actions
            VStack(spacing: 8) {
                Button {
                    coordinator.scheduler.triggerBreakNow(type: .micro)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .frame(width: 18, alignment: .center)
                        Text("Take Micro-Break Now (20s)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(ForestTheme.forest.opacity(0.25))
                    .foregroundStyle(ForestTheme.mist)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.scheduler.triggerBreakNow(type: .long)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .frame(width: 18, alignment: .center)
                        Text("Take Long Break Now (5m)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(ForestTheme.lush.opacity(0.25))
                    .foregroundStyle(ForestTheme.mist)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    if coordinator.scheduler.state.isPaused {
                        coordinator.scheduler.resume()
                    } else {
                        coordinator.scheduler.pause(for: 3600.0) // 1 hour
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: coordinator.scheduler.state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .frame(width: 18, alignment: .center)
                        Text(coordinator.scheduler.state.isPaused ? "Resume Breaks" : "Pause Breaks (1 Hour)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Navigation & Quit
            HStack {
                Button {
                    SettingsWindowController.shared.show(coordinator: coordinator)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings & Stats...")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .font(.footnote)
        }
        .padding(14)
        .frame(width: 290)
        .onAppear {
            coordinator.start()
        }
    }

    private var statusBadge: some View {
        Text(coordinator.scheduler.state.isPaused ? "Paused" : "Active")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(coordinator.scheduler.state.isPaused ? Color.yellow.opacity(0.2) : Color.green.opacity(0.2))
            .foregroundStyle(coordinator.scheduler.state.isPaused ? Color.orange : Color.green)
            .clipShape(Capsule())
    }

    private func formattedMinutes(_ seconds: TimeInterval) -> String {
        let mins = Int(ceil(seconds / 60.0))
        return "in \(mins)m"
    }
}
