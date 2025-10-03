// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {DeFi} from "../src/DeFi-ERC20.sol";

contract CounterScript is Script {
    DeFi public defi;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        defi = new DeFi();

        vm.stopBroadcast();
    }
}
