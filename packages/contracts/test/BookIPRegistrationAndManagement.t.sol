// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockIPGraph} from "@storyprotocol/test/mocks/MockIPGraph.sol";
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {ILicenseRegistry} from "@storyprotocol/core/interfaces/registries/ILicenseRegistry.sol";
import {IPILicenseTemplate} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {IRoyaltyModule} from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {IRoyaltyTokenDistributionWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {IRoyaltyWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {MockERC20} from "@storyprotocol/test/mocks/token/MockERC20.sol";

import {BookIPRegistrationAndManagement} from "../src/BookIPRegistrationAndManagement.sol";
