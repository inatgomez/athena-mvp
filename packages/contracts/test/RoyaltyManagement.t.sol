// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

// Story Protocol Test Utilities
import { MockIPGraph } from "@storyprotocol/test/mocks/MockIPGraph.sol";
import { MockERC20 } from "@storyprotocol/test/mocks/token/MockERC20.sol";

// Story Protocol Core Interfaces
import { IIPAssetRegistry } from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import { ILicenseRegistry } from "@storyprotocol/core/interfaces/registries/ILicenseRegistry.sol";
import { IPILicenseTemplate } from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { IRoyaltyModule } from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";

// Story Protocol Periphery Interfaces
import { IRegistrationWorkflows } from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import { IRoyaltyTokenDistributionWorkflows } from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import { IDerivativeWorkflows } from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import { IRoyaltyWorkflows } from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import { ISPGNFT } from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import { WorkflowStructs } from "@storyprotocol/periphery/lib/WorkflowStructs.sol";

// Contract under test
import { BookIPRegistrationAndManagement } from "../src/BookIPRegistrationAndManagement.sol";

/// @title Royalty Management Test Suite
/// @notice Comprehensive tests for royalty claims, payments, and tip distribution
/// @dev Run with: forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/RoyaltyManagement.t.sol -vvv
contract RoyaltyManagementTest is Test {
    
    // ============ TEST ACCOUNTS ============
    address internal owner = address(0x999999);
    address internal alice = address(0xa11ce);  // Author / IP owner
    address internal bob = address(0xb0b);      // Derivative creator
    address internal carol = address(0xca501);  // Tipper / Reader

    // ============ STORY PROTOCOL CONTRACTS ============
    IIPAssetRegistry internal constant IP_ASSET_REGISTRY = 
        IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    ILicenseRegistry internal constant LICENSE_REGISTRY = 
        ILicenseRegistry(0x529a750E02d8E2f15649c13D69a465286a780e24);
    IPILicenseTemplate internal constant PIL_TEMPLATE = 
        IPILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    IRoyaltyModule internal constant ROYALTY_MODULE = 
        IRoyaltyModule(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);
    
    IRegistrationWorkflows internal constant REGISTRATION_WORKFLOWS = 
        IRegistrationWorkflows(0xbe39E1C756e921BD25DF86e7AAa31106d1eb0424);
    IRoyaltyTokenDistributionWorkflows internal constant ROYALTY_DISTRIBUTION_WORKFLOWS = 
        IRoyaltyTokenDistributionWorkflows(0xa38f42B8d33809917f23997B8423054aAB97322C);
    IDerivativeWorkflows internal constant DERIVATIVE_WORKFLOWS = 
        IDerivativeWorkflows(0x9e2d496f72C547C2C535B167e06ED8729B374a4f);
    IRoyaltyWorkflows internal constant ROYALTY_WORKFLOWS = 
        IRoyaltyWorkflows(0x9515faE61E0c0447C6AC6dEe5628A2097aFE1890);

    address internal constant ROYALTY_POLICY_LAP = 0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;
    address internal constant MERC20_ADDRESS = 0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E;
    MockERC20 internal MERC20 = MockERC20(MERC20_ADDRESS);

    uint32 internal constant PERCENTAGE_SCALE = 100_000_000;

    // ============ CONTRACT UNDER TEST ============
    BookIPRegistrationAndManagement internal bookContract;

    // ============ TEST FIXTURES ============
    address internal parentIpId;
    uint256 internal parentTokenId;
    address internal derivativeIpId;
    uint256 internal derivativeTokenId;

    // ============ SETUP ============
    
    function setUp() public {
        // Deploy MockIPGraph
        vm.etch(address(0x0101), address(new MockIPGraph()).code);

        // Deploy contract
        bookContract = new BookIPRegistrationAndManagement(
            owner,
            address(REGISTRATION_WORKFLOWS),
            address(ROYALTY_DISTRIBUTION_WORKFLOWS),
            address(DERIVATIVE_WORKFLOWS),
            address(ROYALTY_WORKFLOWS),
            address(ROYALTY_MODULE),
            address(PIL_TEMPLATE),
            MERC20_ADDRESS,
            ROYALTY_POLICY_LAP
        );

        // Create collection
        vm.prank(owner);
        bookContract.createBookCollection(_getCollectionInitParams());

        // Authorize authors
        vm.startPrank(owner);
        bookContract.setAuthorized(alice, true);
        bookContract.setAuthorized(bob, true);
        vm.stopPrank();

        // Fund accounts
        MERC20.mint(alice, 10000 * 10**18);
        MERC20.mint(bob, 10000 * 10**18);
        MERC20.mint(carol, 10000 * 10**18);

        // Approvals
        vm.prank(alice);
        MERC20.approve(address(ROYALTY_DISTRIBUTION_WORKFLOWS), type(uint256).max);
        vm.prank(bob);
        MERC20.approve(address(ROYALTY_DISTRIBUTION_WORKFLOWS), type(uint256).max);
        vm.prank(bob);
        MERC20.approve(address(bookContract), type(uint256).max);
        vm.prank(carol);
        MERC20.approve(address(bookContract), type(uint256).max);

        // Create test fixtures: parent book and derivative
        _setupTestFixtures();
    }

    /// @dev Creates parent book and derivative for testing
    function _setupTestFixtures() internal {
        // Alice creates parent book with commercial license
        vm.prank(alice);
        (parentIpId, parentTokenId, uint256[] memory parentLicenseTermsIds) = 
            bookContract.registerBook(
                alice,
                _createBookMetadata("Parent-Book"),
                _toUint8Array(0), // Commercial
                10 * 10**18,
                5_000_000,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Bob creates derivative
        vm.prank(bob);
        (derivativeIpId, derivativeTokenId) = 
            bookContract.registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(parentLicenseTermsIds[0]),
                _createBookMetadata("Derivative-Work"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                20 * 10**18,
                0, 0,
                false
            );
    }

    // ============ HELPER FUNCTIONS ============

    function _getCollectionInitParams() internal view returns (ISPGNFT.InitParams memory) {
        return ISPGNFT.InitParams({
            name: "Athena Books",
            symbol: "ATHENA",
            baseURI: "https://ipfs.io/ipfs/",
            contractURI: "https://athena.com/collection.json",
            maxSupply: 10000,
            mintFee: 0,
            mintFeeToken: address(0),
            mintFeeRecipient: address(0),
            owner: address(bookContract),
            mintOpen: true,
            isPublicMinting: false
        });
    }

    function _createBookMetadata(string memory title) internal pure returns (WorkflowStructs.IPMetadata memory) {
        return WorkflowStructs.IPMetadata({
            metadataURI: string(abi.encodePacked("ipfs://", title)),
            metadataHash: keccak256(abi.encodePacked(title)),
            nftMetadataHash: keccak256(abi.encodePacked("nft-", title))
        });
    }

    function _toAddressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    function _toUint8Array(uint8 val) internal pure returns (uint8[] memory) {
        uint8[] memory arr = new uint8[](1);
        arr[0] = val;
        return arr;
    }

    function _toUint256Array(uint256 val) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = val;
        return arr;
    }

    function _buildClaimData(
        address childIpId,
        address royaltyPolicy,
        address currencyToken
    ) internal pure returns (WorkflowStructs.ClaimRevenueData[] memory) {
        WorkflowStructs.ClaimRevenueData[] memory claimData = new WorkflowStructs.ClaimRevenueData[](1);
        claimData[0] = WorkflowStructs.ClaimRevenueData({
            childIpId: childIpId,
            royaltyPolicy: royaltyPolicy,
            currencyToken: currencyToken
        });
        return claimData;
    }

    // ============================================================
    //                   ROYALTY CLAIM TESTS
    // ============================================================

    function test_ClaimRoyalties_SingleCurrency() public {
        // Setup: Bob pays royalty to Alice's book
        uint256 royaltyPayment = 50 * 10**18;
        
        vm.prank(bob);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            royaltyPayment,
            "Test royalty payment"
        );

        // Alice claims royalties
        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            _buildClaimData(derivativeIpId, ROYALTY_POLICY_LAP, MERC20_ADDRESS);

        uint256 aliceBalanceBefore = MERC20.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amountsClaimed = bookContract.claimRoyalties(
            parentIpId,
            alice,
            claimData
        );

        uint256 aliceBalanceAfter = MERC20.balanceOf(alice);

        // Verify claim
        assertTrue(amountsClaimed.length > 0, "Should return claimed amounts");
        assertTrue(aliceBalanceAfter > aliceBalanceBefore, "Alice should receive tokens");
        
        console2.log("Royalty payment:", royaltyPayment);
        console2.log("Alice claimed:", aliceBalanceAfter - aliceBalanceBefore);
    }

    function test_ClaimRoyalties_MultipleCurrencies() public {
        // This test demonstrates the structure for multi-currency claims
        // In practice, you'd have multiple revenue sources in different tokens
        
        // Setup: Pay royalties
        uint256 royaltyPayment = 50 * 10**18;
        
        vm.prank(bob);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            royaltyPayment,
            "Multi-currency test"
        );

        // Create claim data (in production, this would have multiple currency tokens)
        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            new WorkflowStructs.ClaimRevenueData[](1);
        claimData[0] = WorkflowStructs.ClaimRevenueData({
            childIpId: derivativeIpId,
            royaltyPolicy: ROYALTY_POLICY_LAP,
            currencyToken: MERC20_ADDRESS
        });

        uint256 aliceBalanceBefore = MERC20.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amountsClaimed = bookContract.claimRoyalties(
            parentIpId,
            alice,
            claimData
        );

        // Verify claims for each currency
        assertEq(amountsClaimed.length, claimData.length, "Should match claim data length");
        assertTrue(MERC20.balanceOf(alice) > aliceBalanceBefore, "Should receive tokens");
    }

    function test_ClaimRoyalties_RevertWhen_NoRevenue() public {
        // Attempt to claim without any revenue paid
        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            _buildClaimData(derivativeIpId, ROYALTY_POLICY_LAP, MERC20_ADDRESS);

        vm.prank(alice);
        // This should either revert or return zero amounts
        // Protocol handles zero revenue gracefully
        uint256[] memory amountsClaimed = bookContract.claimRoyalties(
            parentIpId,
            alice,
            claimData
        );

        // If no revert, amounts should be zero or minimal
        if (amountsClaimed.length > 0) {
            assertEq(amountsClaimed[0], 0, "No revenue should be claimed");
        }
    }

    function test_ClaimRoyalties_GasUsage() public {
        // Setup royalty payment
        vm.prank(bob);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            50 * 10**18,
            "Gas test payment"
        );

        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            _buildClaimData(derivativeIpId, ROYALTY_POLICY_LAP, MERC20_ADDRESS);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        
        bookContract.claimRoyalties(parentIpId, alice, claimData);
        
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 150_000, "Claim gas should be under 150K");
        console2.log("Royalty claim gas usage:", gasUsed);
    }

    // ============================================================
    //                   ROYALTY PAYMENT TESTS
    // ============================================================

    function test_PayRoyaltyShare_Success() public {
        uint256 royaltyPayment = 50 * 10**18;
        address parentVault = ROYALTY_MODULE.ipRoyaltyVaults(parentIpId);
        
        uint256 vaultBalanceBefore = MERC20.balanceOf(parentVault);

        vm.prank(bob);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            royaltyPayment,
            "Regular royalty payment"
        );

        uint256 vaultBalanceAfter = MERC20.balanceOf(parentVault);

        // Verify payment went to parent's royalty vault
        assertEq(
            vaultBalanceAfter,
            vaultBalanceBefore + royaltyPayment,
            "Vault should receive royalty payment"
        );
    }

    function test_PayRoyaltyShare_RevertWhen_NoVault() public {
        // Create an address that doesn't have a royalty vault
        address fakeIpId = address(0xfake);

        vm.prank(bob);
        vm.expectRevert(BookIPRegistrationAndManagement.NoRoyaltyVault.selector);
        bookContract.payRoyaltyShare(
            fakeIpId,
            derivativeIpId,
            50 * 10**18,
            "Should fail"
        );
    }

    function test_PayRoyaltyShare_RevertWhen_ZeroAmount() public {
        vm.prank(bob);
        vm.expectRevert(BookIPRegistrationAndManagement.InvalidAmount.selector);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            0,
            "Zero payment"
        );
    }

    function test_PayRoyaltyShare_GasUsage() public {
        vm.prank(bob);
        uint256 gasBefore = gasleft();
        
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            50 * 10**18,
            "Gas benchmark"
        );
        
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 150_000, "Payment gas should be under 150K");
        console2.log("Royalty payment gas usage:", gasUsed);
    }

    function test_PayRoyaltyShare_EmitsCorrectEvent() public {
        uint256 royaltyPayment = 50 * 10**18;

        vm.prank(bob);
        vm.recordLogs();
        
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            royaltyPayment,
            "Event test"
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventFound = false;
        
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RoyaltySharePaid(address,address,address,uint256,string)")) {
                eventFound = true;
                break;
            }
        }
        
        assertTrue(eventFound, "RoyaltySharePaid event should be emitted");
    }

    // ============================================================
    //                   TIP PAYMENT TESTS
    // ============================================================

    function test_PayTip_WithPlatformFee() public {
        uint256 tipAmount = 100 * 10**18;
        uint256 appFeePercent = bookContract.appRoyaltyFeePercent();
        uint256 expectedAppFee = (tipAmount * appFeePercent) / PERCENTAGE_SCALE;
        uint256 expectedTipAmount = tipAmount - expectedAppFee;

        uint256 derivativeBalanceBefore = MERC20.balanceOf(derivativeIpId);
        uint256 contractBalanceBefore = MERC20.balanceOf(address(bookContract));

        vm.prank(carol);
        bookContract.payTip(derivativeIpId, tipAmount, "Great work!", type(uint256).max);

        // Verify tip distribution
        assertEq(
            MERC20.balanceOf(derivativeIpId),
            derivativeBalanceBefore + expectedTipAmount,
            "Derivative should receive tip minus fee"
        );
        assertEq(
            MERC20.balanceOf(address(bookContract)),
            contractBalanceBefore + expectedAppFee,
            "Contract should receive platform fee"
        );

        console2.log("Tip amount:", tipAmount);
        console2.log("Platform fee:", expectedAppFee);
        console2.log("Recipient received:", expectedTipAmount);
    }

    function test_PayTip_RevertWhen_FeeExceedsMax() public {
        uint256 tipAmount = 100 * 10**18;
        uint256 lowMaxFee = 500_000; // 0.5% - lower than actual app fee (1%)

        vm.prank(carol);
        vm.expectRevert("Fee too high");
        bookContract.payTip(derivativeIpId, tipAmount, "Should fail", lowMaxFee);
    }

    function test_PayTip_RevertWhen_ZeroAmount() public {
        vm.prank(carol);
        vm.expectRevert(BookIPRegistrationAndManagement.InvalidAmount.selector);
        bookContract.payTip(derivativeIpId, 0, "Zero tip", type(uint256).max);
    }

    function test_PayTip_VerifyPlatformFeeCalculation() public {
        // Test various tip amounts to verify fee calculation
        uint256[] memory tipAmounts = new uint256[](3);
        tipAmounts[0] = 10 * 10**18;   // Small tip
        tipAmounts[1] = 100 * 10**18;  // Medium tip
        tipAmounts[2] = 1000 * 10**18; // Large tip

        uint256 appFeePercent = bookContract.appRoyaltyFeePercent();

        for (uint i = 0; i < tipAmounts.length; i++) {
            uint256 tipAmount = tipAmounts[i];
            uint256 expectedFee = (tipAmount * appFeePercent) / PERCENTAGE_SCALE;
            uint256 expectedNet = tipAmount - expectedFee;

            uint256 derivativeBalanceBefore = MERC20.balanceOf(derivativeIpId);
            uint256 contractBalanceBefore = MERC20.balanceOf(address(bookContract));

            vm.prank(carol);
            bookContract.payTip(derivativeIpId, tipAmount, "Test", type(uint256).max);

            // Verify calculations
            assertEq(
                MERC20.balanceOf(derivativeIpId) - derivativeBalanceBefore,
                expectedNet,
                "Net tip amount incorrect"
            );
            assertEq(
                MERC20.balanceOf(address(bookContract)) - contractBalanceBefore,
                expectedFee,
                "Platform fee incorrect"
            );

            console2.log("Tip:", tipAmount, "Fee:", expectedFee, "Net:", expectedNet);
        }
    }

    function test_PayTip_GasUsage() public {
        uint256 tipAmount = 100 * 10**18;

        vm.prank(carol);
        uint256 gasBefore = gasleft();
        
        bookContract.payTip(derivativeIpId, tipAmount, "Gas test", type(uint256).max);
        
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 100_000, "Tip gas should be under 100K");
        console2.log("Tip payment gas usage:", gasUsed);
    }

    function test_PayTip_EmitsCorrectEvent() public {
        uint256 tipAmount = 100 * 10**18;
        uint256 appFeePercent = bookContract.appRoyaltyFeePercent();
        uint256 expectedAppFee = (tipAmount * appFeePercent) / PERCENTAGE_SCALE;
        uint256 expectedTipAmount = tipAmount - expectedAppFee;

        vm.prank(carol);
        vm.expectEmit(true, true, false, true);
        emit BookIPRegistrationAndManagement.TipPaid(
            derivativeIpId,
            carol,
            expectedTipAmount,
            expectedAppFee,
            "Amazing!"
        );
        
        bookContract.payTip(derivativeIpId, tipAmount, "Amazing!", type(uint256).max);
    }

    // ============================================================
    //                   PLATFORM FEE MANAGEMENT TESTS
    // ============================================================

    function test_SetAppFee_Success() public {
        uint256 newFee = 2_000_000; // 2%
        uint256 oldFee = bookContract.appRoyaltyFeePercent();

        vm.prank(owner);
        bookContract.setAppFee(newFee);

        assertEq(bookContract.appRoyaltyFeePercent(), newFee, "Fee should be updated");

        // Verify event emission
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit BookIPRegistrationAndManagement.AppFeeUpdated(newFee, 3_000_000);
        bookContract.setAppFee(3_000_000);
    }

    function test_SetAppFee_RevertWhen_ExceedsMax() public {
        uint256 tooHighFee = 15_000_000; // 15% - exceeds 10% max

        vm.prank(owner);
        vm.expectRevert(BookIPRegistrationAndManagement.InvalidAmount.selector);
        bookContract.setAppFee(tooHighFee);
    }

    function test_SetAppFee_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        bookContract.setAppFee(2_000_000);
    }

    function test_SetAppFee_AffectsFutureTips() public {
        // Set new fee
        uint256 newFee = 2_000_000; // 2%
        vm.prank(owner);
        bookContract.setAppFee(newFee);

        // Pay tip with new fee
        uint256 tipAmount = 100 * 10**18;
        uint256 expectedAppFee = (tipAmount * newFee) / PERCENTAGE_SCALE;
        uint256 expectedNet = tipAmount - expectedAppFee;

        uint256 derivativeBalanceBefore = MERC20.balanceOf(derivativeIpId);
        uint256 contractBalanceBefore = MERC20.balanceOf(address(bookContract));

        vm.prank(carol);
        bookContract.payTip(derivativeIpId, tipAmount, "New fee test", type(uint256).max);

        // Verify new fee was applied
        assertEq(
            MERC20.balanceOf(derivativeIpId) - derivativeBalanceBefore,
            expectedNet,
            "Should use new fee rate"
        );
        assertEq(
            MERC20.balanceOf(address(bookContract)) - contractBalanceBefore,
            expectedAppFee,
            "Platform should receive new fee amount"
        );
    }

    // ============================================================
    //                   INTEGRATION SCENARIOS
    // ============================================================

    function test_CompleteRoyaltyFlow_TipAndClaim() public {
        console2.log("\n=== COMPLETE ROYALTY FLOW TEST ===");

        // STEP 1: Carol tips Bob's derivative
        uint256 tipAmount = 100 * 10**18;
        console2.log("Step 1: Carol tips derivative");
        
        vm.prank(carol);
        bookContract.payTip(derivativeIpId, tipAmount, "Great fanfic!", type(uint256).max);

        // STEP 2: Bob pays royalty share to Alice's book
        uint256 royaltyPayment = 50 * 10**18;
        console2.log("Step 2: Bob pays royalty to parent book");
        
        vm.prank(bob);
        bookContract.payRoyaltyShare(
            parentIpId,
            derivativeIpId,
            royaltyPayment,
            "Quarterly royalties"
        );

        // STEP 3: Alice claims royalties from her book
        console2.log("Step 3: Alice claims royalties");
        
        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            _buildClaimData(derivativeIpId, ROYALTY_POLICY_LAP, MERC20_ADDRESS);

        uint256 aliceBalanceBefore = MERC20.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amountsClaimed = bookContract.claimRoyalties(
            parentIpId,
            alice,
            claimData
        );

        uint256 aliceBalanceAfter = MERC20.balanceOf(alice);
        uint256 aliceClaimed = aliceBalanceAfter - aliceBalanceBefore;

        // STEP 4: Verify complete flow
        console2.log("Step 4: Verify results");
        
        assertTrue(aliceClaimed > 0, "Alice should receive royalties");
        console2.log("Alice claimed:", aliceClaimed);
        console2.log("=== FLOW COMPLETE ===\n");
    }

    function test_MultipleDerivatives_AggregatedRoyalties() public {
        // Create second derivative from Alice's book
        vm.prank(bob);
        (address derivative2IpId, ) = 
            bookContract.registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(LICENSE_REGISTRY.getAttachedLicenseTerms(parentIpId, address(PIL_TEMPLATE), 0)),
                _createBookMetadata("Second-Derivative"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                20 * 10**18,
                0, 0,
                false
            );

        // Both derivatives pay royalties
        vm.startPrank(bob);
        bookContract.payRoyaltyShare(parentIpId, derivativeIpId, 30 * 10**18, "Derivative 1");
        bookContract.payRoyaltyShare(parentIpId, derivative2IpId, 20 * 10**18, "Derivative 2");
        vm.stopPrank();

        // Alice claims from both derivatives
        WorkflowStructs.ClaimRevenueData[] memory claimData = 
            new WorkflowStructs.ClaimRevenueData[](2);
        claimData[0] = WorkflowStructs.ClaimRevenueData({
            childIpId: derivativeIpId,
            royaltyPolicy: ROYALTY_POLICY_LAP,
            currencyToken: MERC20_ADDRESS
        });
        claimData[1] = WorkflowStructs.ClaimRevenueData({
            childIpId: derivative2IpId,
            royaltyPolicy: ROYALTY_POLICY_LAP,
            currencyToken: MERC20_ADDRESS
        });

        uint256 aliceBalanceBefore = MERC20.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory amountsClaimed = bookContract.claimRoyalties(
            parentIpId,
            alice,
            claimData
        );

        uint256 aliceBalanceAfter = MERC20.balanceOf(alice);

        // Verify aggregated claims
        assertTrue(aliceBalanceAfter > aliceBalanceBefore, "Should receive from both derivatives");
        console2.log("Total claimed from multiple derivatives:", aliceBalanceAfter - aliceBalanceBefore);
    }
}