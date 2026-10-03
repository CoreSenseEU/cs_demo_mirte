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
//  #        #    #  #    #  #            #  #       #  # #       #  #      //
//  #     #  #    #  #   #   #      #     #  #       #   ##  #    #  #      //
//   #####    ####   #    #  ######  #####   ######  #    #   ####   ###### //
//****************************************************************************/

// Ontology of the MIRTE demonstrator: a robot inferring which room of a
// house it is in from the objects it perceives.

package MIRTE_ontology {

    private import ScalarValues::*;
    private import CSBase::*;

    item def PhysicalObject :> Entity {
        doc /* A thing in the house the robot can perceive. */
    }

    item def Room :> Entity {
        doc /* A room of the house. Its type is not observed directly: it is
               inferred from the objects it contains.

               Each concrete room concept carries an `assert constraint`
               named `classification`: the necessary condition every
               instance of it satisfies. The demonstrator's room estimator
               reads these rules as sufficient conditions too (a room
               satisfying `Kitchen::classification` is taken to be a
               kitchen). */

        derived ref item objectsContained : PhysicalObject [0..*]
            = contains.object {
            doc /* The objects this room contains: the targets of its
                   Contains relations. */
        }

        connection contains : Contains [0..*] {
            doc /* The Contains relations this room is the source of:
                   the knowledge perception reports one observed relation
                   per object seen in the room. */
        }

        // Approximate free-space navigation point in the `map` frame.
        //
        // These coordinates are semantic properties of a concrete room
        // instance. The concrete values are provided by the room
        // instances below.
        attribute navigationX : Real;
        attribute navigationY : Real;
        attribute navigationTheta : Real;

        assert constraint relationsSource {
            doc /* Every Contains relation held by this room has this room
                   as its `room` end. */
            contains->ControlFunctions::forAll {
                in c : Contains; c.room == self
            }
        }

        assert constraint oneRelationPerObject {
            doc /* As many relations as objects. */
            SequenceFunctions::size(contains)
                == SequenceFunctions::size(objectsContained)
        }
    }

    connection def Contains :> BinaryRelation {
        doc /* Relation between a room and an object. */

        end item room :>> source : Room [1];
        end item object :>> target : PhysicalObject [1];
    }

    item def Sofa :> PhysicalObject;
    item def TV :> PhysicalObject;
    item def Bed :> PhysicalObject;
    item def Chair :> PhysicalObject;
    item def DiningTable :> PhysicalObject;
    item def Fridge :> PhysicalObject;
    item def Cup :> PhysicalObject;
    item def Oven :> PhysicalObject;

    enum def RoomType {
        enum LivingRoom;
        enum Bedroom;
        enum Kitchen;
        enum DiningRoom;
    }

    item def LivingRoom :> Room {
        doc /* A room containing a cup and a TV. */

        assert constraint classification {
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype Cup
            } and
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype TV
            }
        }
    }

    item def Bedroom :> Room {
        doc /* A room containing a bed. */

        assert constraint classification {
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype Bed
            }
        }
    }

    item def Kitchen :> Room {
        doc /* A room containing a fridge. */

        assert constraint classification {
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype Fridge
            }
        }
    }

    item def DiningRoom :> Room {
        doc /* A room containing a dining table and a chair. */

        assert constraint classification {
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype DiningTable
            } and
            objectsContained->ControlFunctions::exists {
                in o : PhysicalObject;
                o istype Chair
            }
        }
    }

    attribute def PlanarPose {
        doc /* Position and heading of the base in the odometry frame
               (`odom`), as the base controller reports them: x and y
               in metres, theta in radians counter-clockwise from the
               x axis. */

        attribute x : Real;
        attribute y : Real;
        attribute theta : Real;
    }

    attribute def PlanarVelocity {
        doc /* Velocity of a holonomic base: linear along the heading and
               sideways (metres per second) and angular (radians per
               second), the three components a mecanum drive honours. */

        attribute linearX : Real;
        attribute linearY : Real;
        attribute angular : Real;
    }

    attribute def RoomBelief {
        doc /* How strongly the robot holds itself to be in a room of one
               kind: the evidence its room estimator has accumulated for
               that kind (one unit per inference, decayed over time).
               Compared with the acceptance threshold of the `reachRoom`
               capability. */

        attribute kind : RoomType;
        attribute strength : Real;
    }

    part def MIRTEHouse {

        part bedroom : Bedroom {
            attribute :>> navigationX = -6.20;
            attribute :>> navigationY = -0.50;
            attribute :>> navigationTheta = 0.0;

            part bed : Bed;
        }

        part kitchen : Kitchen {
            attribute :>> navigationX = 7.20;
            attribute :>> navigationY = -1.50;
            attribute :>> navigationTheta = 0.0;

            part fridge : Fridge;
            part oven : Oven;
        }

        part livingRoom : LivingRoom {
            attribute :>> navigationX = 1.20;
            attribute :>> navigationY = -2.90;
            attribute :>> navigationTheta = 0.0;

            part sofa : Sofa;
            part tv : TV;
            part cup : Cup;
        }

        part diningRoom : DiningRoom {
            attribute :>> navigationX = 1.20;
            attribute :>> navigationY = 3.60;
            attribute :>> navigationTheta = 0.0;

            part diningTable : DiningTable;
            part chair : Chair;
        }
    }


    // Concrete instance of the MIRTE house.
    part mirteHouse : MIRTEHouse;
}