//****************************************************************************/
//                                                                          //
//  Copyright (c) 2022-2026 The CORESENSE Consortium.                       //
//  This code was forged in the fires of innovation by the CORESENSE        //
//  Consortium dwarves. We're releasing it into the wild. Be nice to it.    //
//                                                                          //
//  Licensed under the Apache License, Version 2.0 (the "License");         //
//                                                                          //
//  http://www.apache.org/licenses/LICENSE-2.0                              //
//                                                                          //
//  http://www.coresense.eu                                                 //
//                                                                          //
//   #####                           #####                                  //
//  #     #   ####   #####   ###### #     #  ######  #    #   ####   ###### //
//  #        #    #  #    #  #      #        #       ##   #  #       #      //
//  #        #    #  #    #  #####   #####   #####   # #  #   ####   #####  //
//  #        #    #  #####   #            #  #       #  # #       #  #      //
//  #     #  #    #  #   #   #      #     #  #       #   ##  #    #  #      //
//   #####    ####   #    #  ######  #####   ######  #    #   ####   ###### //
//****************************************************************************/

// Architecture of the MIRTE demonstrator: the cognitive modules involved,
// where each is deployed, what each one runs, and how they are coupled.
//
// The system is one `CSSystem` of the reference: six subsystems, one ROS 2
// lifecycle node each (`understanding`, `perception`, `meta`, `action`,
// `master`, `governance`), four of them the reference packages unchanged
// and two (`perception`, `action`) the demonstrator's own, replacing the
// reference by interface. Three cognitive modules live under them:
//
// - `objectDetector`, under Perception: the third-party YOLO stack
//   (yolo_ros).
// - `roomEstimator`, under Understanding: the demonstrator's room
//   estimator, the tutorial's symbolic reasoning and belief management in
//   one module, an external consumer of Understanding's query contract.
// - `mirteModule`, under Runtime: the executing module Master deploys,
//   which drives the base and decides when a room is reached.

package MIRTE_architecture {

    private import ScalarValues::*;
    private import CSBase::*;
    private import CSCore::*;
    private import CSStructure::*;
    private import CSRuntime::RuntimeArchitecture::*;
    private import CSArchitecture::*;
    private import MIRTE_ontology::*;
    private import MIRTE_selfModel::*;

    // In CSCore a core realizes its cognitive function by executing Models 
    // through an Engine; these are the three pairs of the demonstrator.

    part objectDetectionModel : Model {
        doc /* The object detector's trained weights (YOLOv8, `yolov8m.pt`):
               a third-party, opaque model of what household objects look
               like. Its classes are mapped to the ontology's concepts by
               the perception node, outside the module. */
    }

    part objectDetectionEngine : Engine {
        doc /* The detector's inference (ultralytics), with 3D localization 
               from the depth image. */
    }

    part roomClassificationModel : Model {
        doc /* The MIRTE ontology's room concepts and their `classification`
               rules, read from Understanding, plus the belief state
               `mirte.locationBelief` they feed. */
    }

    part roomEstimationEngine : Engine {
        doc /* Evaluates the rules over the Contains relations of the current
               room, then raises the belief of every kind inferred and decays
               all of them. */
    }

    part motionPolicyModel : Model {
        doc /* The `explore` policy: how the base is driven while the kind of
               the current room is unknown, expressed as `move` commands. */
    }

    part motionEngine : Engine {
        doc /* Turns the policy into velocity references for the base, and
               checks the belief against the acceptance threshold. */
    }

    part mirteSystem : CSSystem {
        doc /* The CS-FE system controlling `mirte`: one lifecycle node per
               subsystem, Governance the initial node driving the others
               through their lifecycle. */

        part :>> perS {
            doc /* Node `perception`, the demonstrator's own (package
                   `cs_demo_mirte`), replacing cs_perception by interface.
                   Extract: takes the detector's 3D detections, keeps those
                   within `mirte.camera.detectionRange`, maps their classes to
                   the ontology's PhysicalObject concepts, and reports each
                   as an ObjectDetected plus a `contains` RelationObserved
                   from the current room. Also reports the base's pose and
                   velocity as AttributeObserved on `mirte`. */

            part objectDetector : ROS2CognitiveModule :> modules {
                doc /* The YOLO detection stack (yolo_ros), third party: its
                       nodes run as launched by yolo_bringup. */
                attribute :>> name = "yolo";
                part :>> afferent {
                    attribute :>> subscribedTopics = (
                        "/rgbd_camera/image", "/rgbd_camera/depth_image",
                        "/rgbd_camera/camera_info");
                }
                part :>> core {
                    ref :>> model = objectDetectionModel;
                    ref :>> engine = objectDetectionEngine;
                }
                part :>> efferent {
                    attribute :>> publishedTopics = ("/yolo/detections_3d");
                    attribute :>> messageTypes = ("yolo_msgs/msg/DetectionArray");
                }
            }
        }

        part :>> undS {
            doc /* Node `understanding` (cs_understanding, unchanged): loads the
                   MIRTE ontology as the ontology layer, and MIRTE_selfModel as 
                   the SelfModel; assimilates the observations, serves the queries, 
                   derives the Context. */

            part roomEstimator : ROS2CognitiveModule :> modules {
                doc /* The demonstrator's room estimator (node `room_estimator`,
                       package `cs_demo_mirte`): the tutorial's symbolic node
                       and knowledge management node as one module. On every
                       Context it queries the WorldModel for the current room's
                       objects, evaluates each room concept's `classification`
                       rule, updates the beliefs and reports them, with the
                       committed `location`, as AttributeObserved on `mirte`.
                       Understanding's SenseMake, realized outside the
                       reference node, over its stable query contract. */
                attribute :>> name = "room_estimator";
                part :>> afferent {
                    attribute :>> subscribedTopics = ("/context");
                    attribute :>> messageTypes = ("cs_interfaces/msg/Context");
                }
                part :>> core {
                    ref :>> model = roomClassificationModel;
                    ref :>> engine = roomEstimationEngine;
                    attribute beliefIncrement : Real = 1.0 {
                        doc /* Added to the belief of every kind inferred in a cycle. */
                    }
                    attribute beliefDecay : Real = 0.8 {
                        doc /* Every belief is multiplied by it at every cycle:
                               how fast the robot forgets. */
                    }
                }
                part :>> efferent {
                    attribute :>> publishedTopics = ("/features/attributes");
                    attribute :>> messageTypes = ("cs_interfaces/msg/AttributeObserved");
                }
            }
        }

        part :>> govS {
            doc /* Node `governance` (cs_governance, unchanged): bootstraps the
                   nodes, plans the mission's desired effects into one task
                   each (`reach_kitchen`, `reach_bedroom`), dispatches them in
                   order and re-plans on failure. The mission is
                   MIRTE_mission::tour, handed over as a Mission message. */

            item visitRooms : CognitiveProcess :> processes {
                doc /* The one cognitive process of the demonstrator: detect,
                       estimate, act, over the whole structure. */
                ref :>> structure = mirteStructure;
                ref :>> activeModules = (
                    mirteSystem.perS.objectDetector,
                    mirteSystem.undS.roomEstimator,
                    mirteSystem.runS.mirteModule);
            }
        }

        part :>> runS {
            doc /* Node `master` (cs_runtime, unchanged): forwards each 
                   specification to the module and relays its reports. */

            part mirteModule : ROS2CognitiveModule :> modules {
                doc /* The executing module, assembled from the demonstrator's
                       components with the reference default meta and
                       coupling. It realizes the `reachRoom` capability the
                       SelfModel declares: drives the base through
                       `mirte.mecanumBase.move` under the `explore` policy
                       until `mirte.locationBelief` for the requested kind
                       reaches `reachRoom.acceptanceThreshold`, then reports
                       SUCCEEDED; FAILED on the task's deadline. */
                attribute :>> name = "mirte_module";
                ref :>> capabilities = mirte.reachRoom;
                part :>> afferent {
                    attribute :>> subscribedTopics = ("~/action_specification");
                    attribute :>> messageTypes = ("cs_interfaces/msg/ActionSpecification");
                }
                part :>> core {
                    ref :>> model = motionPolicyModel;
                    ref :>> engine = motionEngine;
                }
                part :>> efferent {
                    attribute :>> publishedTopics = ("/cmd_vel", "~/execution_status");
                    attribute :>> messageTypes = (
                        "geometry_msgs/msg/Twist", "cs_interfaces/msg/ExecutionStatusReport");
                }
            }
        }

        part :>> actS {
            doc /* Node `action`, the demonstrator's own (package
                   `cs_demo_mirte`), replacing cs_action by interface: for each
                   task, turns the planned action `reach_<kind>` into one
                   assignment of `reachRoom` for that RoomType, to
                   `mirte_module`, with the policy (`explore`) and the kind in
                   the assignment's JSON parameters. */
        }

        part :>> metS {
            doc /* Node `meta` (cs_meta, unchanged): awareness from the
                   execution status stream. */
        }
    }

    item mirteStructure : CognitiveStructure {
        doc /* Detections become Contains relations the estimator reasons
               over; the estimator's beliefs decide the executing module's
               termination. */
        ref :>> modules = (
            mirteSystem.perS.objectDetector,
            mirteSystem.undS.roomEstimator,
            mirteSystem.runS.mirteModule);

        connection detectionsToEstimation : ModuleCoupling :> couplings
            connect mirteSystem.perS.objectDetector to mirteSystem.undS.roomEstimator;

        connection beliefsToExecution : ModuleCoupling :> couplings
            connect mirteSystem.undS.roomEstimator to mirteSystem.runS.mirteModule;
    }
}