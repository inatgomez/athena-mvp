// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { WIP } from "../src/WIP.sol";

contract Deploy is Script {
    WIP public wip;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("STORY_PRIVATEKEY"));
        wip = new WIP();
        vm.stopBroadcast();
    }
}
