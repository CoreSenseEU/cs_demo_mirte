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

package MIRTE_mission {

    private import ScalarValues::*;
    private import CSBase::*;
    private import MIRTE_ontology::*;
    private import MIRTE_selfModel::*;

    part robotInHouse : ExtendedSystem {
        doc /* The Mirte Master in the house: the extended system the mission,
               its context and its goals are stated over. */
        part :>> targetSystem = mirte;
        part :>> environmentEntities : Room [0..*] {
            doc /* The rooms of the house, as the WorldModel holds them. */
        }
        part :>> environment {
            ref :>> system = mirte;
            ref :>> entities = environmentEntities;
        }
    }

    item tourContext : Context {
        doc /* The context the mission is given in: the runtime Context
               Understanding derives (`cs_interfaces/msg/Context`) is this one,
               kept current. Nothing is known about the house beforehand. */
        ref :>> extendedSystem = robotInHouse;
        attribute :>> conditions = "the kind of the room the robot is in is unknown until inferred";
    }

    item reachKitchen : Goal {
        doc /* The robot is in a kitchen. */
        ref :>> extendedSystem = robotInHouse;
        occurrence :>> desiredStates : SystemState [1] {
            ref :>> entity = robotInHouse;
            assert constraint inKitchen {
                mirte.location istype Kitchen
            }
        }
    }

    item reachBedroom : Goal {
        doc /* The robot is in a bedroom. */
        ref :>> extendedSystem = robotInHouse;
        occurrence :>> desiredStates : SystemState [1] {
            ref :>> entity = robotInHouse;
            assert constraint inBedroom {
                mirte.location istype Bedroom
            }
        }
    }

    item tour : Mission {
        doc /* Visit the kitchen, then the bedroom. */
        ref :>> context = tourContext;
        attribute :>> desiredEffects = ("reach_kitchen", "reach_bedroom");
    }
}
