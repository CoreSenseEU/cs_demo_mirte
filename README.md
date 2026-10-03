# MIRTE Cognitive Architecture Demo

ROS 2 Jazzy demonstration of a model-driven cognitive architecture for the MIRTE robot.

The system combines:

- A SysML v2 system model.
- Automatic generation of an OWL ontology from the SysML model.
- Semantic extraction of navigation goals from the OWL ontology.
- EasyNav for robot navigation.
- YOLO-based object detection.
- Ontology-based semantic verification of the destination room.

The main idea is that room names, navigation poses and room verification rules are not hardcoded in the ROS node. They are obtained from the generated OWL ontology.

---

## Install

Install all the required dependencies by running:

```bash
chmod +x install.sh
./install.sh
```

The script adds the repositories required for the cognitive architecture tutorial to the ROS 2 workspace created during the previous ROS 2 session.

If you do **NOT** already have the simulator installed, also run:

```bash
wget https://raw.githubusercontent.com/IntelligentRoboticsLabs/docker_infrastructure/main/docker/installation_scripts/simulator.sh
chmod +x simulator.sh
./simulator.sh
```

---

## Usage

### 1. Generating the OWL ontology

The SysML model can be translated using `sysml2owl`.

Example:

```bash
ros2 run sysml2owl sysml2owl \
    ~/ros2_ws/src/cs_demo_mirte/model/MIRTE_ontology.sysml \
    ~/ros2_ws/src/cs_demo_mirte/model/MIRTE_selfModel.sysml \
    ~/ros2_ws/src/cs_demo_mirte/model/MIRTE_architecture.sysml \
    ~/ros2_ws/src/cs_demo_mirte/model/MIRTE_mission.sysml \
    --base-iri https://coresense.eu/mirte# \
    --output ~/ros2_ws/src/cs_demo_mirte/ontology/sysml.owl
```

The generated ontology is:

```text
cs_demo_mirte/ontology/sysml.owl
```

### 2. Running the MIRTE demo

The demo requires several terminals.

Activate the environment:

```bash
cd ~/ros2_ws
source venv_cogarchs/bin/activate
source install/setup.bash
```

Launch the MIRTE simulation:

```bash
ros2 launch cs_demo_mirte mirte_demo.launch.py
```

This launches the MIRTE simulation and the components defined by the demo launch file.

In a second terminal:

```bash
cd ~/ros2_ws
```

Start EasyNav:

```bash
ros2 run easynav_system system_main \
    --ros-args \
    -r odom:=/mirte_base_controller/odometry \
    --params-file /home/esther/ros2_ws/src/cs_demo_mirte/config/easynav_params.yaml
```

Then send a command, i.e., any room available in the knowledge base.

```bash
ros2 topic pub --once \
    /mirte/action \
    std_msgs/msg/String \
    "{data: kitchen}"
```

---

## Description

### 1. Architecture

The execution flow is:

```text
                     SysML v2 model
                           |
                           v
                    +-------------+
                    |  sysml2owl  |
                    +-------------+
                           |
                           v
                       sysml.owl
                           |
                           |
            +--------------+--------------+
            |                             |
            v                             v
     Room navigation                 Room semantics
     (navigationX/Y/Theta)           (classification rules)
            |                             |
            +--------------+--------------+
                           |
                           v
                  mirte_module_node
                    /           \
                   /             \
                  v               v
             EasyNav             YOLO
            navigation        detections_3d
                  |               |
                  |               v
                  |        observed objects
                  |               |
                  +-------+-------+
                          |
                          v
                  Semantic verification
                          |
                          v
                    Room verified
```

The ROS node `mirte_module_node` acts as the mission-level module.

When a room command is received:

1. The requested room is looked up in the OWL ontology.
2. Its navigation pose is extracted from OWL.
3. A navigation goal is sent to EasyNav.
4. YOLO detections are accumulated during the mission.
5. Once navigation reaches the target room, the ontology classification rule is evaluated.
6. The room is considered verified when all required objects have been detected.

For example, the ontology can define:

```text
Kitchen -> requires Fridge
Bedroom -> requires Bed
LivingRoom -> requires Cup and TV
DiningRoom -> requires DiningTable and Chair
```

The ROS node does not contain this information as a hardcoded dictionary.

### 2. SysML model

The MIRTE system model is located in:

```text
cs_demo_mirte/model/
```

The model is divided into several SysML files:

```text
MIRTE_ontology.sysml
MIRTE_selfModel.sysml
MIRTE_architecture.sysml
MIRTE_mission.sysml
```

The ontology model defines, among other things:

- physical objects;
- rooms;
- room/object containment;
- navigation poses;
- room classification rules;
- MIRTE house structure.

Example:

```sysml
part kitchen : Kitchen {
    attribute navigationX : Real = 7.20;
    attribute navigationY : Real = -1.50;
    attribute navigationTheta : Real = 0.0;

    part fridge : Fridge;
    part oven : Oven;
}
```

The room classification rules are defined semantically in SysML.

For example, a `Kitchen` requires a `Fridge`:

```text
Kitchen -> Fridge
```

These semantic rules are automatically translated into OWL restrictions (using object and data properties), which enforce that the navigation task is complete only when the robot reaches the requested room and satisfies all associated constraints (e.g., presence of required objects like a Fridge in the Kitchen).

### 3. Design principle

The key design principle of the demo is:

> **The ROS runtime should execute the knowledge contained in the system model rather than duplicate that knowledge in application code.**

Consequently:

- room poses come from OWL;
- concrete rooms come from OWL;
- room classification requirements come from OWL;
- object detections come from YOLO;
- navigation is delegated to EasyNav;
- mission-level reasoning is performed by `mirte_module_node`.

This separation allows the SysML model to evolve without requiring room-specific changes in the ROS implementation.
