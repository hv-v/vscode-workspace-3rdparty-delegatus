# SHIRE-1590 — out of concept: physical quantities with an undetermined unit

Companion to [1590-table.md](1590-table.md), same columns, filtered to a single
criterion:

> **Fields that are physical quantities — a temperature, a length, an angle, a
> voltage, a time, a speed — but whose current unit I could not determine from
> the message definition.**

These are the rows where I am **not confident enough to write a conversion
formula**. Every one of them needs an answer from whoever owns the producing
node before SHIRE-1590 can touch it. Guessing a factor here would silently
corrupt real measurements, which is exactly the failure the unit system exists
to prevent.

- **Paths** are relative to `/home/vhaponov/Documents/jo-workspace/jen-interfaces-modules/`.
- **Target Unit** is the unit the Shire spec implies for that quantity — the
  destination is usually clear even when the source is not.
- **Conversion Formula** states the specific open question instead of a formula.
- These rows also appear in `1590-table.md`; that file is unchanged and remains
  the complete picture. This file is the subset that needs a human answer.

**29 rows.**

| Name | Path | Variable Name | Current Unit | Target Unit | Conversion Formula |
|---|---|---|---|---|---|
| CameraParameters | `jen_camera_msgs/msg/CameraParameters.msg` | `gain_factor` | — (undefined) | dimensionless factor, or `Decibels` if logarithmic | ❓ Is this a linear factor or dB? The two differ by `20*log10(x)` |
| ImageMetadata | `jen_camera_msgs/msg/ImageMetadata.msg` | `latitude` | — (undefined) | `Degrees.msg` (deg) | ❓ deg or rad? Factor `180/π` apart. Comment gives semantics but never the unit |
| ImageMetadata | `jen_camera_msgs/msg/ImageMetadata.msg` | `longitude` | — (undefined) | `Degrees.msg` (deg) | ❓ deg or rad? Factor `180/π` apart |
| Point2D | `jen_detector_msgs/jen_detector_msgs/msg/Point2D.msg` | `x` | — (undefined) | `Meters.msg` (m), if it is a world coordinate | ❓ Image pixels or world metres? No comment anywhere in the file |
| Point2D | `jen_detector_msgs/jen_detector_msgs/msg/Point2D.msg` | `y` | — (undefined) | `Meters.msg` (m), if it is a world coordinate | ❓ Image pixels or world metres? |
| PowerSupplyStatus | `jen_hal_msgs/msg/PowerSupplyStatus.msg` | `voltage` | — (undefined) | `Volts.msg` (V) | ❓ V or mV? The file contains no comments at all |
| PowerSupplyStatus | `jen_hal_msgs/msg/PowerSupplyStatus.msg` | `current` | — (undefined) | `Amperes.msg` (A) | ❓ A or mA? Note `FalconSensorReadings` uses mA elsewhere in the tree |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_fpga` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown. An `int16` temperature is usually deci-°C or centi-°C, not whole °C |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_laser` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see `temp_fpga` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_adc` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see `temp_fpga` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_board` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see `temp_fpga` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_det[4]` | — (undefined, `int16`) | `Celsius.msg[4]` (°C) | ❓ Vendor scale unknown — see `temp_fpga` |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `temp_other[3]` | — (undefined, `int16`) | `Celsius.msg[3]` (°C) | ❓ Vendor scale unknown, and the three elements are not even named |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `galvo_offset_angle_client` | — (undefined, `uint16`) | `Radians.msg` (rad) or `Degrees.msg` (deg) | ❓ Genuinely undecidable — the spec permits **both** rad and deg, so neither is a safe default. Also `uint16`, so a scale factor is likely |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `moisture_index[2]` | arbitrary index | `Percent.msg[2]` (%) | ❓ Is this a 0–100 scale, 0–65535, or a vendor code? A physical humidity reading with an undocumented scale |
| FalconSensorReadings | `jen_lidar_falcon_driver_msgs/msg/FalconSensorReadings.msg` | `window_blockage_index[2]` | arbitrary index | `Percent.msg[2]` (%) | ❓ Same question as `moisture_index` |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_fpga` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown. Must resolve identically to the `FalconSensorReadings` copy |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_adc` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see above |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_board` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see above |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_laser` | — (undefined, `int16`) | `Celsius.msg` (°C) | ❓ Vendor scale unknown — see above |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `temp_det[4]` | — (undefined, `int16`) | `Celsius.msg[4]` (°C) | ❓ Vendor scale unknown — see above |
| FalconStatus | `jen_lidar_falcon_driver_msgs/msg/FalconStatus.msg` | `uptime` | — (undefined, `float64`) | `builtin_interfaces/Duration` | ❓ Seconds is likely, but never stated. The same file's siblings spell it out (`power_up_time_in_second`), this one does not |
| FalconStatusCounters | `jen_lidar_falcon_driver_msgs/msg/FalconStatusCounters.msg` | `lifelong_uptime` | — (undefined, `uint32`) | `builtin_interfaces/Duration` | ❓ Seconds, minutes or hours? A lifetime counter in `uint32` seconds overflows at ~136 years, so seconds is plausible but unconfirmed |
| LidarAlignmentBFotoLine | `jen_sr355_alignment_msgs/msg/LidarAlignmentBFotoLine.msg` | `distance` | — (undefined, `float32`) | `Meters.msg` (m) | ❓ Metres or image pixels? The message has no comment and sits in an alignment package that mixes both |
| LidarAlignmentTriggerLine | `jen_sr355_alignment_msgs/msg/LidarAlignmentTriggerLine.msg` | `distance` | — (undefined, `float32`) | `Meters.msg` (m) | ❓ Metres or pixels? `coordinate_system` is a sibling string field, which suggests it may vary at runtime |
| CameraImageParameters | `jen_sr355_alignment_msgs/msg/CameraImageParameters.msg` | `gain` | — (undefined, `float64`) | dimensionless factor, or `Decibels` if logarithmic | ❓ Linear factor or dB? Marked "draft; ported from the external DORA type", so the source convention is unverified |
| LidarAlignmentImageRequest | `jen_sr355_alignment_msgs/msg/LidarAlignmentImageRequest.msg` | `gain` | — (undefined, `float64`) | dimensionless factor, or `Decibels` if logarithmic | ❓ Linear factor or dB? Must match `CameraImageParameters.gain` |
| LidarAlignmentParameterValue | `jen_sr355_alignment_msgs/msg/LidarAlignmentParameterValue.msg` | `value` | — (undefined, `float32`) | varies per parameter | ❓ A generic value carrying any physical quantity. Cannot be typed at all without a registry mapping `key` → unit |
| ObjectTrack3D | `jen_vision_msgs/msg/ObjectTrack3D.msg` | `velocity` | — (undefined, `Vector3`) | m·s⁻¹ | ❓ **The highest-risk row.** m/s or km/h? Two other speed fields in `jen_vision_msgs` are explicitly km/h, so the wrong assumption here is a 3.6× error on a measured speed |

---

## What is grouped how

| group | rows | the open question |
|---|---|---|
| Falcon `int16` temperatures | 11 | one vendor scale factor answers all of them at once |
| Angles (`latitude`, `longitude`, `galvo_offset_angle_client`) | 3 | deg or rad — the spec allows both, so there is no safe default |
| Camera/imager `gain` | 3 | linear factor or dB |
| Lengths (`distance` ×2, `Point2D.x/y`) | 4 | metres or pixels |
| Electrical (`voltage`, `current`) | 2 | base unit or milli- prefix |
| Time (`uptime`, `lifelong_uptime`) | 2 | almost certainly seconds, but unstated |
| Sensor indices (`moisture`, `window_blockage`) | 2 | what scale the index runs on |
| Speed (`velocity`) | 1 | m/s or km/h — a 3.6× error if guessed wrong |
| Generic (`LidarAlignmentParameterValue.value`) | 1 | needs a `key` → unit registry to be typeable at all |

**Answering just three questions clears 17 of the 29 rows:** the Falcon
temperature scale (11), the angle convention (3), and the gain convention (3).

---

## Deliberately excluded, and why

These are uncertain or non-compliant too, but they fail the filter for this file
— they are not "a physical quantity whose unit I could not determine".

| excluded | rows | why |
|---|---|---|
| Bytes and pixels (`mem_*`, `swap_*`, `*_bytes`, `*_px`, `character_height`, `model_input_*`) | 14 | I **am** sure what these are. The problem is that the Shire unit system does not cover them — a spec decision, not a measurement question. See §1.2 of the report |
| Confidence scores (`confidence_speed/pose/dimension`, `vrn_confidence`, `country_confidence`) | 5 | Undocumented ranges, but confidence is not a physical quantity |
| `LidarAlignmentTriggerLine.direction` | 1 | Needs an enum definition, not a unit |
| `LidarAlignmentImage.binning` | 1 | Dimensionless by nature; I am confident it is a plain integer factor |
| `Lane`/`TriggerLine`/`TriggerZone` geometry | 5 | `geometry_msgs/Point` is metres by REP-103. The unit is unstated but not genuinely in doubt — it needs a comment, not an answer |
| Fields with a known wrong unit (`speed` km/h ×2, `motor_rpm`, `galvo_fpm`, `heater_current_ma`, `latency_10us_*`, `netstat_*_kbps`, `clock_diff_ms`, `threshold_ms`, `timestamp`, `power_up_time_in_second`, `process_up_time_in_second`) | 15 | The current unit is documented and the formula is unambiguous. These are ready to implement, not open questions |
| Correct unit, wrong encoding (`*_pct`, `*_p`, `*_percentage`, `temperature_c`, `power_w`, `*_deg`, `confidence_*` 0–100) | 26 | The unit is known and right; only the type needs to change. Pure `1:1` wrapping work |

29 listed here + 67 excluded = the 96 rows of `1590-table.md`.

If you want any of these folded in — the bytes/pixels group is the most
defensible addition, since it is also unactionable — say which and I will extend
the table.
