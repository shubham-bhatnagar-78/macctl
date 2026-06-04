[Skip to content](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#start-of-content)

You signed in with another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md) to refresh your session.You signed out in another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md) to refresh your session.You switched accounts on another tab or window. [Reload](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md) to refresh your session.Dismiss alert

{{ message }}

[openclaw](https://github.com/openclaw)/ **[Peekaboo](https://github.com/openclaw/Peekaboo)** Public

- [Notifications](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo) You must be signed in to change notification settings
- [Fork\\
342](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo)
- [Star\\
4.6k](https://github.com/login?return_to=%2Fopenclaw%2FPeekaboo)


## Collapse file tree

## Files

main

Search this repository(forward slash)` forward slash/`

/

# ARCHITECTURE.md

Copy path

Blame

More file actions

Blame

More file actions

## Latest commit

![vyctorbrzezowski](https://avatars.githubusercontent.com/u/51521767?v=4&size=40)![steipete](https://avatars.githubusercontent.com/u/58493?v=4&size=40)

[vyctorbrzezowski](https://github.com/openclaw/Peekaboo/commits?author=vyctorbrzezowski)

and

[steipete](https://github.com/openclaw/Peekaboo/commits?author=steipete)

[docs: soften platform and provider reference language](https://github.com/openclaw/Peekaboo/commit/f7d9d042e95d798fc72e708ec9a375ce5999e975)

3 weeks agoMay 17, 2026

[f7d9d04](https://github.com/openclaw/Peekaboo/commit/f7d9d042e95d798fc72e708ec9a375ce5999e975) · 3 weeks agoMay 17, 2026

## History

[History](https://github.com/openclaw/Peekaboo/commits/main/docs/ARCHITECTURE.md)

Open commit details

[View commit history for this file.](https://github.com/openclaw/Peekaboo/commits/main/docs/ARCHITECTURE.md) History

255 lines (196 loc) · 12 KB

/

# ARCHITECTURE.md

Top

## File metadata and controls

- Preview

- Code

- Blame


255 lines (196 loc) · 12 KB

[Raw](https://github.com/openclaw/Peekaboo/raw/refs/heads/main/docs/ARCHITECTURE.md)

Copy raw file

Download raw file

Outline

Edit and raw actions

| summary | Review Peekaboo Architecture Overview guidance |
| read\_when | |     |     |
| --- | --- |
| planning work related to peekaboo architecture overview | debugging or extending features described here | |

# Peekaboo Architecture Overview

[Permalink: Peekaboo Architecture Overview](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#peekaboo-architecture-overview)

This document provides a high-level overview of how Tachikoma and PeekabooCore work together to provide AI-powered macOS automation capabilities.

## System Architecture

[Permalink: System Architecture](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#system-architecture)

### Core Components

[Permalink: Core Components](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#core-components)

```
┌─────────────────┐
│   Tachikoma     │  AI models + streaming
└────────┬────────┘
         │
┌────────▼────────┐      ┌────────────────────┐      ┌────────────────────┐
│ PeekabooAutomation│◄───►│ PeekabooAgentRuntime │◄───►│  PeekabooVisualizer  │
│ UI/system services│      │ Agent + MCP runtime │      │ Visual feedback stack │
└────────┬────────┘      └──────────┬──────────┘      └──────────┬──────────┘
         │                           │                           │
         └───────────────┬───────────┴───────────┬───────────────┘
                         ▼                       ▼
                  ┌─────────────┐        ┌──────────────┐
                  │  PeekabooCore│        │   Apps / CLI │
                  │ (umbrella)   │        │  consumers   │
                  └─────────────┘        └──────────────┘
```

- **PeekabooAutomation** – houses _all_ automation-facing code (configuration, capture, application/menu/window services, snapshot management, typed models). Anything that touches Accessibility, ScreenCaptureKit, or on-host configuration lives here.
- **PeekabooVisualizer** – standalone visual feedback layer (`VisualizationClient`, event store, presets) used by automation and apps.
- **PeekabooAgentRuntime** – MCP tools, ToolRegistry/formatters, and the agent service itself. Depends on `PeekabooAutomation` for services/data models and on `PeekabooVisualizer` for status tokens.
- **PeekabooCore** – thin umbrella (`_exported` imports + `PeekabooServices` convenience container). Apps/CLI keep importing `PeekabooCore`, but large features can now link the more focused products directly. Whoever instantiates `PeekabooServices` is responsible for calling `installAgentRuntimeDefaults()` so MCP tools and the ToolRegistry share that instance.
- **Tachikoma** – still the AI provider surface that the runtime modules call through. See
[providers.md](https://github.com/openclaw/Peekaboo/blob/main/docs/providers.md) for the current provider and model catalog.

### Dependency Flow

[Permalink: Dependency Flow](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#dependency-flow)

**Tachikoma** (AI Model Management)

- Provides `AIModelProvider` for dependency injection.
- Manages provider/model registry, model selection, and capability metadata.
- Handles API configuration and credential management.

**PeekabooAutomation**

- Depends on Tachikoma for provider metadata and `PeekabooVisualizer` for optional UI feedback.
- Exposes pure Swift protocols (`ApplicationServiceProtocol`, `LoggingServiceProtocol`, etc.) plus concrete implementations (MenuService, ScreenCaptureService, ProcessService, etc.).
- Owns persisted models such as `CaptureTarget`, `AutomationAction`, `UIElement`, `SnapshotInfo`, and shared helper utilities.

**PeekabooAgentRuntime**

- Imports `PeekabooAutomation` for services/models and hosts MCP/agent tooling (`PeekabooAgentService`, `MCPToolContext`, `ToolRegistry`, CLI/MCP formatters).
- Provides a clean `PeekabooServiceProviding` protocol so higher layers (CLI, macOS app, and the MCP server entrypoints) can swap concrete service collections without touching globals.

**PeekabooVisualizer**

- Stays decoupled from automation; only consumes `PeekabooProtocols` data (`DetectedElement`, `LogLevel`) so it can be embedded in other contexts later.
- `VisualizationClient` is still accessed via `PeekabooAutomation` convenience wrappers, but the module boundary keeps visual dependencies out of headless hosts.

## Tachikoma: AI Model Management

[Permalink: Tachikoma: AI Model Management](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#tachikoma-ai-model-management)

### Architecture Pattern: Dependency Injection

[Permalink: Architecture Pattern: Dependency Injection](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#architecture-pattern-dependency-injection)

Tachikoma has migrated from a singleton pattern to dependency injection for better testability and flexibility:

```
// Old (deprecated)
let model = try await Tachikoma.shared.getModel("gpt-4.1")

// New (recommended)
let provider = try AIConfiguration.fromEnvironment()
let model = try provider.getModel("gpt-4.1")
```

### Key Components

[Permalink: Key Components](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#key-components)

#### AIModelProvider

[Permalink: AIModelProvider](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#aimodelprovider)

- **Role**: Central registry for AI model instances
- **Pattern**: Immutable collection with functional updates
- **Thread Safety**: Full concurrent access support

#### AIModelFactory

[Permalink: AIModelFactory](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#aimodelfactory)

- **Role**: Factory methods for creating model instances
- **Supported Providers**: See [providers.md](https://github.com/openclaw/Peekaboo/blob/main/docs/providers.md) for the current provider reference
- **Configuration**: Handles API keys, base URLs, and model-specific parameters

#### AIConfiguration

[Permalink: AIConfiguration](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#aiconfiguration)

- **Role**: Environment-based automatic configuration
- **Sources**: Environment variables and `~/.tachikoma/credentials` file
- **Auto-Discovery**: Automatically registers all available models

## PeekabooCore: Automation Engine

[Permalink: PeekabooCore: Automation Engine](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#peekaboocore-automation-engine)

### Architecture Pattern: Service Orchestration

[Permalink: Architecture Pattern: Service Orchestration](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#architecture-pattern-service-orchestration)

PeekabooCore uses a service locator pattern with specialized service delegation:

```
let services = PeekabooServices()
let automation = services.automation  // UIAutomationService
let screenCapture = services.screenCapture  // ScreenCaptureService
let applications = services.applications  // ApplicationService
```

### Service Hierarchy

[Permalink: Service Hierarchy](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#service-hierarchy)

#### PeekabooServices (Service Locator)

[Permalink: PeekabooServices (Service Locator)](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#peekabooservices-service-locator)

- **Role**: Central registry for all automation services
- **Pattern**: Service locator with dependency injection support
- **Lifecycle**: Manages service initialization and coordination

##### Installing a services instance

[Permalink: Installing a services instance](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#installing-a-services-instance)

`PeekabooServices` no longer registers itself globally. Whoever constructs an instance (CLI runtime, macOS app, integration test, etc.) **must** call `services.installAgentRuntimeDefaults()` immediately after initialization. This wires the container into `MCPToolContext` and `ToolRegistry` so downstream tooling (MCP server, CLI `peekaboo tools`, agent service) can resolve the exact same services without touching singletons. Skipping the install step will cause MCP and ToolRegistry code to fatal because no default factory is configured.

#### UIAutomationService (Orchestrator)

[Permalink: UIAutomationService (Orchestrator)](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#uiautomationservice-orchestrator)

- **Role**: Primary automation interface delegating to specialized services
- **Delegation**: Routes operations to appropriate specialized services
- **Snapshot Management**: Maintains state across automation workflows

#### Specialized Services

[Permalink: Specialized Services](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#specialized-services)

Each service handles a specific aspect of automation:

- **ClickService**: Mouse interaction and element targeting
- **TypeService**: Keyboard input and text manipulation
- **ScreenCaptureService**: Display and window capture
- **ApplicationService**: Application discovery and management
- **WindowManagementService**: Window positioning and state control
- **MenuService**: Menu bar navigation and interaction
- **SnapshotManager**: State persistence and element caching

### Threading Model

[Permalink: Threading Model](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#threading-model)

**Main Thread Requirement**: All UI automation operations run on MainActor due to macOS requirements:

```
@MainActor
public final class UIAutomationService: UIAutomationServiceProtocol {
    // All operations are main-thread bound
}
```

### Integration Points

[Permalink: Integration Points](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#integration-points)

#### AI Integration

[Permalink: AI Integration](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#ai-integration)

PeekabooCore integrates with Tachikoma through `PeekabooAgentService`:

```
let modelProvider = try AIConfiguration.fromEnvironment()
let agent = PeekabooAgentService(
    services: PeekabooServices(),
    modelProvider: modelProvider
)
```

#### Visual Feedback Integration

[Permalink: Visual Feedback Integration](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#visual-feedback-integration)

Services automatically connect to PeekabooVisualizer when available:

```
// Automatic visualizer integration
let visualizerClient = VisualizationClient.shared
_ = await visualizerClient.showClickFeedback(at: clickPoint, type: clickType)
```

Behind the scenes the client serializes a `VisualizerEvent` into `~/Library/Application Support/PeekabooShared/VisualizerEvents/<uuid>.json` and posts `boo.peekaboo.visualizer.event` via `NSDistributedNotificationCenter`. When Peekaboo.app is alive its `VisualizerEventReceiver` loads the payload and hands it to `VisualizerCoordinator`; otherwise the event is silently dropped and execution continues.

## Data Flow Architecture

[Permalink: Data Flow Architecture](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#data-flow-architecture)

### Automation Workflow

[Permalink: Automation Workflow](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#automation-workflow)

1. **Input**: Natural language task or direct API call
2. **AI Processing**: `PeekabooAgentService` uses Tachikoma models
3. **Service Orchestration**: `UIAutomationService` delegates to specialized services
4. **Platform Integration**: Services use macOS APIs (Accessibility, ScreenCaptureKit)
5. **Visual Feedback**: Operations trigger visualizer animations
6. **Snapshot Management**: State cached for subsequent operations

### Example Flow: "Click the Submit button"

[Permalink: Example Flow: "Click the Submit button"](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#example-flow-click-the-submit-button)

```
User Input ("Click Submit")
    ↓
PeekabooAgentService (AI interpretation)
    ↓
UIAutomationService.detectElements() → ElementDetectionService
    ↓
UIAutomationService.click() → ClickService
    ↓
macOS Accessibility APIs
    ↓
VisualizationClient (click animation)
```

## Performance Characteristics

[Permalink: Performance Characteristics](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#performance-characteristics)

### Service Performance Ranges

[Permalink: Service Performance Ranges](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#service-performance-ranges)

- **Element Detection**: 200-800ms (AI analysis + accessibility correlation)
- **Click Operations**: 10-50ms (accessibility API optimization)
- **Screen Capture**: 20-100ms (ScreenCaptureKit acceleration)
- **Application Discovery**: 20-200ms (depending on system load)
- **Window Management**: 10-200ms (depending on operation complexity)

### Optimization Strategies

[Permalink: Optimization Strategies](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#optimization-strategies)

- **Snapshot Caching**: Element detection results cached per snapshot
- **Accessibility Timeouts**: Reduced from 6s to 2s to prevent hangs
- **Dual APIs**: Modern ScreenCaptureKit with CGWindowList fallback
- **Visual Feedback**: Async animations don't block automation operations

## Error Handling Strategy

[Permalink: Error Handling Strategy](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#error-handling-strategy)

### Layered Error Handling

[Permalink: Layered Error Handling](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#layered-error-handling)

1. **Service Level**: Individual services handle API-specific errors
2. **Orchestration Level**: UIAutomationService provides unified error handling
3. **Agent Level**: AI agent handles retry logic and error recovery
4. **Client Level**: Applications receive structured error information

### Defensive Programming

[Permalink: Defensive Programming](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#defensive-programming)

- **Permission Validation**: Automatic checks for Screen Recording and Accessibility permissions
- **Timeout Protection**: Configurable timeouts prevent system hangs
- **Graceful Degradation**: Fallback strategies for problematic applications
- **State Validation**: Element existence and accessibility verification

## Configuration Management

[Permalink: Configuration Management](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#configuration-management)

### Multi-Source Configuration

[Permalink: Multi-Source Configuration](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#multi-source-configuration)

1. **Environment Variables**: `PEEKABOO_AI_PROVIDERS`, `OPENAI_API_KEY`, etc.
2. **Credential Files**: `~/.peekaboo/config.json`, `~/.tachikoma/credentials`
3. **Runtime Parameters**: Method-level configuration overrides
4. **Feature Flags**: `PEEKABOO_USE_MODERN_CAPTURE`, etc.

### Configuration Precedence

[Permalink: Configuration Precedence](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#configuration-precedence)

```
CLI Arguments > Environment Variables > Credential Files > Config Files > Defaults
```

## Future Architecture Considerations

[Permalink: Future Architecture Considerations](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#future-architecture-considerations)

### Scalability

[Permalink: Scalability](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#scalability)

- Service architecture supports horizontal scaling through additional specialized services
- AI model provider supports multiple concurrent model instances
- Snapshot management designed for multi-user and multi-process scenarios

### Extensibility

[Permalink: Extensibility](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#extensibility)

- Plugin architecture possible through service locator pattern
- AI model provider supports custom model implementations
- Visual feedback system can be extended with additional visualization types

### Cross-Platform Potential

[Permalink: Cross-Platform Potential](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md#cross-platform-potential)

- Service interfaces abstract platform-specific implementations
- Threading model adaptable to other platforms
- AI integration remains platform-agnostic

* * *

_This architecture has been designed to be "really easy for other people to understand" while providing the performance and reliability needed for production automation workflows._

You can’t perform that action at this time.