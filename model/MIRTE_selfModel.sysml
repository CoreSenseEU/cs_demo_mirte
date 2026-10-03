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

package MIRTE_selfModel {

    private import ScalarValues::*;
    private import CSBase::*;
    private import MIRTE_ontology::*;

    part mirte : System, Agent {
        doc /* Mirte Master: the system the mission is given to. 
               A holonomic mecanum base carrying an RGBD camera, a 2D lidar,
               four ultrasonic rangers and an IMU. */

        attribute pose : PlanarPose {
            doc /* Where the base is, from the base controller's odometry.*/
        }

        attribute velocity : PlanarVelocity {
            doc /* How the base is moving, from the same odometry. */
        }

        ref item location : Room [0..1] {
            doc /* The room the robot holds itself to be in: the conclusion of
                   the demonstrator's room estimator, which infers it from the
                   objects the camera sees. Absent until something is inferred;
                   how strongly it is believed is `locationBelief`. */
        }

        attribute locationBelief : RoomBelief [0..*] {
            doc /* The robot's belief about the kind of room it is in, one
                   strength per kind: the room estimator's evidence, raised by
                   every inference of that kind and decayed at every cycle. */
        }

        part camera : Sensor :> components {
            doc /* The Orbbec Astra Plus Pro RGBD camera on the front of the
                   base. What the object detector works on: it
                   observes the physical objects of the environment, each with 
                   its distance. */
            ref :>> observes : PhysicalObject [0..*];
            attribute detectionRange : Real = 3.0 {
                doc /* Distance, in metres, beyond which a detected object is 
                not taken as seen in the current room. The perception node's 
                parameter must agree with it. */
            }
        }

        part lidar : Sensor :> components {
            doc /* The 2D laser scanner on top of the base. */
        }

        part ultrasonicRangers : Sensor [4] :> components {
            doc /* The four range sensors at the corners of the base. */
        }

        part imu : Sensor :> components {
            doc /* The inertial unit of the base: observes the robot itself. */
            ref :>> observes = mirte;
        }

        part odometry : Sensor :> components {
            doc /* The base controller's odometry, computed from the wheel
                   encoders (`/mirte_base_controller/odom`, frame `odom`).
                   What `pose` and `velocity` come from: observes the robot
                   itself. */
            ref :>> observes = mirte;
        }

        part mecanumBase : Actuator :> components {
            doc /* The holonomic base: four mecanum wheels under a mecanum
                   drive controller that takes a velocity reference. */
            attribute command : PlanarVelocity;
            attribute wheelRadius : Real = 0.051 {
                doc /* Metres, from the base controller's kinematics */
            }

            perform action move : Actions::Action :> executes {
                doc /* Drive the base at a velocity for a duration. */
                in velocity : PlanarVelocity [1];
                in duration : Real [1] {
                    doc /* Seconds; the reference is renewed by the executor until then. */
                }
            }
            ref :>> commandedBy = mirte;
        }

        perform mecanumBase.move :> commands {
            doc /* The agent commands the base's motion; the base executes it. */
        }

        item reachRoom : Capability {
            doc /* Being in a room of a requested kind. Exercised through a policy
                chosen by Action (exploring while the current room's kind is
                unknown). */
            ref :>> system = mirte;
            ref :>> realizes = reachRoomFunction;
            attribute :>> conditions = (
                "a room of the requested kind exists",
                "the room contains the objects its classification rule requires, within the camera's detection range"
            );
            attribute :>> acceptanceCriteria =
                "the belief of being in a room of the requested kind reaches acceptanceThreshold";
            attribute acceptanceThreshold : Real = 1.5 {
                doc /* Belief strength from which the requested kind of room is
                       taken as reached: `locationBelief` for that kind at or
                       above it ends the task with success. */
            }
        }

        item reachRoomFunction : Function {
            doc /* Maps a kind of room (RoomType) to the robot being in one. */
            in attribute :>> inputs : RoomType [1];
            out attribute :>> outputs [0];
        }

    }
}