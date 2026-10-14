Just an example of how the parameter is seting up from the config manager.

```
#include "jen_scene_manager/SceneManagerNode.hpp"

#include <chrono>
#include <functional>
#include <jen_logging/logging.hpp>
#include <memory>
#include <string>

using jen_config_manager_interface::srv::SetNodeParameters;

namespace {
constexpr auto SET_SCENE_PARAMETER_SERVICE   = "/jen_scene_manager/set_scene_parameter";

constexpr auto PUBLISH_TOPIC_PARAMETER       = "topic";
constexpr auto SCENE_PARAMETER               = "scene";
constexpr auto MAX_LANES_PARAMETER           = "max_lanes";
constexpr auto MAX_Y_DIFF_PARAMETER          = "max_y_diff";
constexpr auto TRIGGER_ZONES_EMPTY_PARAMETER = "trigger_zones_empty";
constexpr auto DIAGNOSTIC_HEALTH_PARAMETER   = "diagnostics.health";
}  // namespace

SceneManagerNode::SceneManagerNode(std::shared_ptr<ISceneValidator> sceneValidator, const rclcpp::NodeOptions& options)
    : Node("jen_scene_manager", options), sceneValidator_{std::move(sceneValidator)} {
    LOGI(get_logger(), "constructor", "Starting jen_scene_manager node...");

    // ---- Node configuration ----
    // Since declareConfigManagedParameter also assings callbacks that will deserialize yaml
    // to make parameterHandle_ validate result of this we need to run it last.
    // Order is not guaranteed by ROS, so current approach inserting validation callback first
    // is workaround, probably adjustment to declareConfigManagedParameter are required
    parameterHandle_ =
        add_post_set_parameters_callback(std::bind_front(&SceneManagerNode::onConfigurationReceived, this));

    declare_parameter(PUBLISH_TOPIC_PARAMETER, rclcpp::PARAMETER_STRING);
    declare_parameter(MAX_LANES_PARAMETER, rclcpp::PARAMETER_INTEGER);
    declare_parameter(MAX_Y_DIFF_PARAMETER, rclcpp::PARAMETER_DOUBLE);
    declare_parameter(TRIGGER_ZONES_EMPTY_PARAMETER, rclcpp::PARAMETER_BOOL);
    declare_parameter(DIAGNOSTIC_HEALTH_PARAMETER, rclcpp::PARAMETER_STRING);

    // should be after PUBLISH_TOPIC_PARAMETER, since SCENE triggers publish,
    // but publisher is avaible after PUBLISH_TOPIC_PARAMETER is received
    declareConfigManagedParameter(SCENE_PARAMETER, scene_);

    // Node pre-configuration is done - retrieve node's parameters with the following call:
    jen_config_manager_lib_cpp::initializeFromConfigManager(this);
    throwOnUninitializedParams();

    validateReadOnlyParams();
    // ---- Create services only if configuration was successful ----
    initServices();
}

void SceneManagerNode::validateReadOnlyParams() {
    if (const auto maxLanes = get_parameter(MAX_LANES_PARAMETER).as_int(); maxLanes < 0) {
        throw std::runtime_error{"Max lanes cannot be less than 0"};
    } else {
        sceneValidator_->setMaxLanes(static_cast<std::size_t>(maxLanes));
        LOGI(get_logger(), "validateReadOnlyParams", std::format("Max lanes changed to {}", maxLanes));
    }

    if (const auto maxYDiff = get_parameter(MAX_Y_DIFF_PARAMETER).as_double(); maxYDiff < 0) {
        throw std::runtime_error{"Max Y diff cannot be less than 0"};
    } else {
        LOGI(get_logger(), "validateReadOnlyParams", std::format("Max Y diff changed to {}", maxYDiff));
        sceneValidator_->setMinMaxYDiff(maxYDiff);
    }

    if (const auto topic = get_parameter(PUBLISH_TOPIC_PARAMETER).as_string(); topic.empty()) {
        throw std::runtime_error{"Publish topic can not be empty"};
    } else {
        scenePublisher_ = create_publisher<Scene>(topic, 10);
        LOGI(get_logger(), "validateReadOnlyParams", std::format("Scene publisher for topic {} created", topic));
        publishSceneIfValid();
    }

    const auto triggerZonesEmpty = get_parameter(TRIGGER_ZONES_EMPTY_PARAMETER).as_bool();
    sceneValidator_->setTriggerZonesEmpty(triggerZonesEmpty);
}

void SceneManagerNode::initServices() {
    diagUpdater_ = std::make_shared<diagnostic_updater::Updater>(this);
    diagUpdater_->setHardwareID("none");

    auto healthInfoTaskName = this->get_parameter(DIAGNOSTIC_HEALTH_PARAMETER).as_string();
    diagUpdater_->add(healthInfoTaskName, this, &SceneManagerNode::onHealthUpdateNeeded);
    LOGI(get_logger(), "initDiagnosticUpdater",
         std::format("Diagnostic updater is created. Task: {}", healthInfoTaskName));

    setSceneParameterService_ = create_service<SetSceneParameter>(
        SET_SCENE_PARAMETER_SERVICE,
        [this](SceneManagerNode::SetSceneServicePtr service, std::shared_ptr<rmw_request_id_t> requestHeader,
               const std::shared_ptr<jen_scene_msgs::srv::SetSceneParameter_Request>& message) {
            onSceneParameterReceived(service, requestHeader, message);
        });
    LOGI(get_logger(), "constructor", std::format("service {} created", SET_SCENE_PARAMETER_SERVICE));
}

void SceneManagerNode::onHealthUpdateNeeded(diagnostic_updater::DiagnosticStatusWrapper& stat) {
    if (isConfigValid_) {
        stat.summary(diagnostic_msgs::msg::DiagnosticStatus::OK, configValidityMsg_);
    } else {
        stat.summary(diagnostic_msgs::msg::DiagnosticStatus::ERROR, configValidityMsg_);
    }
}

void SceneManagerNode::setConfigState(bool isValid, std::string message) {
    isConfigValid_     = isValid;
    configValidityMsg_ = std::move(message);
}

void SceneManagerNode::throwOnUninitializedParams() const {
    auto nodeParams = list_parameters({}, 0);
    // This method may throw the rclcpp::exceptions::ParameterUninitializedException exception
    get_parameters(nodeParams.names);
}

void SceneManagerNode::publishSceneIfValid() {
    if (!isConfigValid_) {
        return;
    }
    if (scenePublisher_ == nullptr) {
        LOGW(get_logger(), "publishSceneIfValid", "Scene publisher not initialized; scene has not been published.");
        return;
    }
    scenePublisher_->publish(scene_);
    LOGI(get_logger(), "publishSceneIfValid", "Scene published");
}

jen_config_manager_interface::msg::NodeParameters SceneManagerNode::convert(const Scene& scene) const {
    jen_config_manager_interface::msg::NodeParameters nodeParameters;
    rcl_interfaces::msg::Parameter parameter;
    rcl_interfaces::msg::ParameterValue value;

    parameter.set__name(SCENE_PARAMETER);
    value.set__type(rclcpp::ParameterType::PARAMETER_STRING);
    value.set__string_value(jen_parameter_msgs::msg::to_yaml(scene));
    parameter.set__value(value);

    nodeParameters.set__node_name(get_fully_qualified_name());
    nodeParameters.set__parameters(std::vector{parameter});

    return nodeParameters;
}

void SceneManagerNode::onConfigurationReceived(const std::vector<rclcpp::Parameter>& parameters) {
    for (const auto& parameter : parameters) {
        const auto& name = parameter.get_name();
        LOGI(get_logger(), "onConfigurationReceived", std::format("Received parameter {}", name));

        if (name == SCENE_PARAMETER) {
            std::pair<bool, std::string> configState;
            try {
                sceneValidator_->validate(scene_.scene);
                LOGI(get_logger(), "onConfigurationReceived", "Scene updated");
                configState = {true, "Config is valid"};
            } catch (const SceneValidationException& e) {
                LOGW(get_logger(), "onConfigurationReceived", std::format("Scene validation failed {}", e.what()));
                configState = {false, e.what()};
            }
            setConfigState(configState.first, configState.second);
            publishSceneIfValid();
            continue;
        }
    }
}
```