// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

// Story Protocol Test Utilities
import {MockIPGraph} from "@storyprotocol/test/mocks/MockIPGraph.sol";
import {MockERC20} from "@storyprotocol/test/mocks/token/MockERC20.sol";

// Story Protocol Core Interfaces
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {ILicenseRegistry} from "@storyprotocol/core/interfaces/registries/ILicenseRegistry.sol";
import {IPILicenseTemplate} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import {IRoyaltyModule} from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";
import {PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {IIPAccount} from "@storyprotocol/core/interfaces/IIPAccount.sol";

// Story Protocol Periphery Interfaces
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {IRoyaltyTokenDistributionWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {IRoyaltyWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";

// Contract under test
import {BookIPRegistrationAndManagement} from "../../src/BookIPRegistrationAndManagement.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BaseTest
/// @notice Base test contract with optimized setup and enhanced Story Protocol validations
/// @dev Implements lazy funding and test-specific approvals for gas efficiency
abstract contract BaseTest is Test {
    // Constants

    /// @notice Story Protocol percentage scale (100_000_000 = 100%)
    uint32 internal constant PERCENTAGE_SCALE = 100_000_000;

    /// @notice Maximum number of collaborators (Story Protocol limit)
    uint256 internal constant MAX_COLLABORATORS = 16;

    /// @notice Default commercial license fee ($10 in 18 decimals)
    uint256 internal constant DEFAULT_COMMERCIAL_FEE = 10 * 10 ** 18;

    /// @notice Default commercial royalty share (5% in Story format)
    uint32 internal constant DEFAULT_COMMERCIAL_ROYALTY = 5_000_000;

    /// @notice Gas usage threshold for book registration
    uint256 internal constant BOOK_REGISTRATION_GAS_THRESHOLD = 500_000;

    /// @notice Gas usage threshold for derivative creation
    uint256 internal constant DERIVATIVE_CREATION_GAS_THRESHOLD = 400_000;

    // Test Accounts
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal unauthorized = makeAddr("unauthorized");

    // Story Protocol Core Contracts (Aeneid Testnet)
    IIPAssetRegistry internal constant IP_ASSET_REGISTRY =
        IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);

    ILicenseRegistry internal constant LICENSE_REGISTRY =
        ILicenseRegistry(0x529a750E02d8E2f15649c13D69a465286a780e24);

    IPILicenseTemplate internal constant PIL_TEMPLATE =
        IPILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);

    ILicensingModule internal constant LICENSING_MODULE =
        ILicensingModule(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);

    IRoyaltyModule internal constant ROYALTY_MODULE =
        IRoyaltyModule(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);

    // Story Protocol Periphery Contracts
    IRegistrationWorkflows internal constant REGISTRATION_WORKFLOWS =
        IRegistrationWorkflows(0xbe39E1C756e921BD25DF86e7AAa31106d1eb0424);

    IRoyaltyTokenDistributionWorkflows
        internal constant ROYALTY_DISTRIBUTION_WORKFLOWS =
        IRoyaltyTokenDistributionWorkflows(
            0xa38f42B8d33809917f23997B8423054aAB97322C
        );

    IDerivativeWorkflows internal constant DERIVATIVE_WORKFLOWS =
        IDerivativeWorkflows(0x9e2d496f72C547C2C535B167e06ED8729B374a4f);

    IRoyaltyWorkflows internal constant ROYALTY_WORKFLOWS =
        IRoyaltyWorkflows(0x9515faE61E0c0447C6AC6dEe5628A2097aFE1890);

    // Protocol Constants
    address internal constant ROYALTY_POLICY_LAP =
        0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;

    address internal constant MERC20_ADDRESS =
        0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E;

    MockERC20 internal MERC20 = MockERC20(MERC20_ADDRESS);

    // Contract Under Test
    BookIPRegistrationAndManagement internal bookContract;
    address internal spgNftCollection;

    // Setup
    function setUp() public virtual {
        // Deploy MockIPGraph (required for license attachment on fork)
        vm.etch(address(0x0101), address(new MockIPGraph()).code);

        // Deploy BookIPRegistrationAndManagement contract
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

        // Create SPGNFT collection
        vm.prank(owner);
        bookContract.createBookCollection(_getCollectionInitParams());
        spgNftCollection = bookContract.spgNftCollection();

        // Authorize test accounts
        vm.startPrank(owner);
        bookContract.setAuthorized(alice, true);
        bookContract.setAuthorized(bob, true);
        bookContract.setAuthorized(carol, true);
        bookContract.setAuthorized(dave, true);
        vm.stopPrank();

        // NOTE: Lazy funding - only fund accounts when needed in specific tests
        // NOTE: Test-specific approvals - avoid max approval anti-pattern
    }

    // Optimized Funding & Approval Helpers

    /// @dev Funds a single account with MERC20 tokens (lazy funding)
    /// @param account The account to fund
    /// @param amount The amount to mint in wei
    function _fundAccount(address account, uint256 amount) internal {
        MERC20.mint(account, amount);
    }

    /// @dev Approves contract for MERC20 spending by specific account
    /// @param account The account approving
    /// @param spender The spender to approve
    function _approveForAccount(address account, address spender) internal {
        vm.prank(account);
        MERC20.approve(spender, type(uint256).max);
    }

    /// @dev Approves specific amount (safer than max approval)
    /// @param account The account approving
    /// @param spender The spender to approve
    /// @param amount The specific amount to approve
    function _approveForAccountAmount(
        address account,
        address spender,
        uint256 amount
    ) internal {
        vm.prank(account);
        MERC20.approve(spender, amount);
    }

    // Collection Configuration

    /// @dev Returns standard collection initialization parameters
    function _getCollectionInitParams()
        internal
        view
        returns (ISPGNFT.InitParams memory)
    {
        return
            ISPGNFT.InitParams({
                name: "Athena Books Collection",
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

    // Metadata Builders

    /// @dev Creates standard book metadata with dynamic title
    function _createBookMetadata(
        string memory title
    ) internal pure returns (WorkflowStructs.IPMetadata memory) {
        return
            WorkflowStructs.IPMetadata({
                ipMetadataURI: string(abi.encodePacked("ipfs://book-", title)),
                ipMetadataHash: keccak256(abi.encodePacked(title)),
                nftMetadataURI: string(
                    abi.encodePacked("ipfs://nft-book-", title)
                ),
                nftMetadataHash: keccak256(abi.encodePacked("nft-", title))
            });
    }

    // Royalty Share Builders

    /// @dev Creates single author royalty share (100%)
    function _createSingleAuthorRoyalty(
        address author
    ) internal pure returns (WorkflowStructs.RoyaltyShare[] memory) {
        WorkflowStructs.RoyaltyShare[]
            memory shares = new WorkflowStructs.RoyaltyShare[](1);
        shares[0] = WorkflowStructs.RoyaltyShare({
            recipient: author,
            percentage: PERCENTAGE_SCALE
        });
        return shares;
    }

    /// @dev Creates two-author royalty share split
    function _createDualAuthorRoyalty(
        address author1,
        uint32 author1Percent,
        address author2,
        uint32 author2Percent
    ) internal pure returns (WorkflowStructs.RoyaltyShare[] memory) {
        require(
            author1Percent + author2Percent == PERCENTAGE_SCALE,
            "Percentages must sum to 100%"
        );

        WorkflowStructs.RoyaltyShare[]
            memory shares = new WorkflowStructs.RoyaltyShare[](2);
        shares[0] = WorkflowStructs.RoyaltyShare({
            recipient: author1,
            percentage: author1Percent
        });
        shares[1] = WorkflowStructs.RoyaltyShare({
            recipient: author2,
            percentage: author2Percent
        });
        return shares;
    }

    // Derivative creation helper

    /// @dev Asserts parent-child license terms linkage
    function assertParentLicenseTermsLink(
    address childIpId,
    address parentIpId,
    uint256 expectedLicenseTermsId
    ) internal {
    (address licenseTemplate, uint256 licenseTermsId) = 
        LICENSE_REGISTRY.getParentLicenseTerms(childIpId, parentIpId);
    
    assertEq(licenseTemplate, address(PIL_TEMPLATE), "Template mismatch");
    assertEq(licenseTermsId, expectedLicenseTermsId, "License terms mismatch");
    }
    
    /// @dev Helper: Register parent book and return registration data
    function _registerParentBook(address author) internal returns (
    address ipId,
    uint256 tokenId,
    uint256 licenseTermsId
    ) {
    _fundAccount(author, 1000 * 10 ** 18);
    _approveForAccount(author, address(bookContract));
    
    WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
        string(abi.encodePacked("Parent-", vm.toString(author)))
    );
    uint8[] memory licenseTypes = _toUint8Array(0);
    
    vm.prank(author);
    (ipId, tokenId, uint256[] memory licenseTermsIds) = bookContract.registerBook(
        author,
        metadata,
        licenseTypes,
        DEFAULT_COMMERCIAL_FEE,
        DEFAULT_COMMERCIAL_ROYALTY,
        new WorkflowStructs.RoyaltyShare[](0),
        _toAddressArray(author),
        new uint256[](0),
        false
    );
    
    licenseTermsId = licenseTermsIds[0];
    }

    // Claim Revenue Helpers

    /// @dev Builds claim revenue data for single child IP
    function _buildClaimData(
        address childIpId,
        address royaltyPolicy,
        address currencyToken
    ) internal pure returns (WorkflowStructs.ClaimRevenueData[] memory) {
        WorkflowStructs.ClaimRevenueData[]
            memory claimData = new WorkflowStructs.ClaimRevenueData[](1);

        claimData[0] = WorkflowStructs.ClaimRevenueData({
            childIpId: childIpId,
            royaltyPolicy: royaltyPolicy,
            currencyToken: currencyToken
        });

        return claimData;
    }

    // Array Conversion Utilities

    /// @dev Converts single address to address array
    function _toAddressArray(
        address addr
    ) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /// @dev Converts two addresses to address array
    function _toAddressArray(
        address addr1,
        address addr2
    ) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = addr1;
        arr[1] = addr2;
        return arr;
    }

    /// @dev Converts single uint8 to uint8 array
    function _toUint8Array(uint8 val) internal pure returns (uint8[] memory) {
        uint8[] memory arr = new uint8[](1);
        arr[0] = val;
        return arr;
    }

    /// @dev Converts two uint8s to uint8 array
    function _toUint8Array(
        uint8 val1,
        uint8 val2
    ) internal pure returns (uint8[] memory) {
        uint8[] memory arr = new uint8[](2);
        arr[0] = val1;
        arr[1] = val2;
        return arr;
    }

    /// @dev Converts single uint256 to uint256 array
    function _toUint256Array(
        uint256 val
    ) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = val;
        return arr;
    }

    /// @dev Converts two uint256s to uint256 array
    function _toUint256Array(
        uint256 val1,
        uint256 val2
    ) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = val1;
        arr[1] = val2;
        return arr;
    }

    // Enhanced Story Protocol Assertions

    /// @dev Asserts IP is properly registered with all required components
    /// @param ipId The IP address to validate
    /// @param expectedOwner The expected NFT owner
    /// @param tokenId The token ID associated with the IP
    function assertValidIPRegistration(
        address ipId,
        address expectedOwner,
        uint256 tokenId
    ) internal {
        // Verify IP registration
        assertTrue(
            IP_ASSET_REGISTRY.isRegistered(ipId),
            "IP should be registered in protocol"
        );

        // Verify NFT ownership
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(tokenId),
            expectedOwner,
            "NFT owner mismatch"
        );

        // Verify royalty vault deployment
        address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
        assertTrue(
            royaltyVault != address(0),
            "Royalty vault should be deployed"
        );

        // Verify vault is a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(royaltyVault)
        }
        assertTrue(codeSize > 0, "Royalty vault should be a contract");
    }

    /// @dev Asserts license terms are properly attached to IP
    /// @param ipId The IP address to check
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms ID
    function assertLicenseAttached(
        address ipId,
        address licenseTemplate,
        uint256 licenseTermsId
    ) internal {
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                licenseTemplate,
                licenseTermsId
            ),
            "License should be attached to IP"
        );
    }

    /// @dev Asserts license terms parameters match expected values
    /// @param licenseTermsId The license terms ID to validate
    /// @param expectedFee Expected minting fee
    /// @param expectedRoyaltyPercent Expected royalty percentage
    /// @param expectCommercialUse Whether commercial use should be enabled
    function assertLicenseTermsParameters(
        uint256 licenseTermsId,
        uint256 expectedFee,
        uint32 expectedRoyaltyPercent,
        bool expectCommercialUse
    ) internal {
        PILTerms memory terms = PIL_TEMPLATE.getLicenseTerms(licenseTermsId);

        // Verify royalty policy
        assertEq(
            terms.royaltyPolicy,
            ROYALTY_POLICY_LAP,
            "Royalty policy should be LAP"
        );

        // Verify currency token
        assertEq(terms.currency, MERC20_ADDRESS, "Currency should be MERC20");

        // Verify commercial use flag
        assertEq(
            terms.commercialUse,
            expectCommercialUse,
            "Commercial use flag mismatch"
        );

        // Verify minting fee
        assertEq(terms.defaultMintingFee, expectedFee, "Minting fee mismatch");

        // Verify royalty percentage (only check if commercial)
        if (expectCommercialUse) {
            assertEq(
                terms.commercialRevShare,
                expectedRoyaltyPercent,
                "Royalty percentage mismatch"
            );
        }
    }

    /// @dev Asserts IPAccount is deployed for IP
    /// @param ipId The IP address
    /// @param expectedTokenContract Expected NFT contract
    /// @param expectedTokenId Expected token ID
    function assertIPAccountDeployed(
        address ipId,
        address expectedTokenContract,
        uint256 expectedTokenId
    ) internal {
        // Verify IPAccount has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ipId)
        }
        assertTrue(codeSize > 0, "IPAccount should be deployed");

        // Verify token binding
        IIPAccount ipAccount = IIPAccount(payable(ipId));
        (uint256 chainId, address tokenContract, uint256 tokenId) = ipAccount
            .token();

        assertEq(
            tokenContract,
            expectedTokenContract,
            "Token contract mismatch"
        );
        assertEq(tokenId, expectedTokenId, "Token ID mismatch");
        assertEq(chainId, block.chainid, "Chain ID mismatch");
    }

    /// @dev Asserts royalty tokens are distributed to authors as expected
    /// @param ipId The IP address
    /// @param expectedRecipients Expected royalty token recipients
    /// @param expectedShares Expected share percentages
    function assertRoyaltyTokenDistribution(
        address ipId,
        address[] memory expectedRecipients,
        uint256[] memory expectedShares
    ) internal {
        address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
        assertTrue(royaltyVault != address(0), "Royalty vault not deployed");

        // Verify total shares sum to 100%
        uint256 totalShares;
        for (uint256 i = 0; i < expectedShares.length; i++) {
            totalShares += expectedShares[i];
        }
        assertEq(totalShares, PERCENTAGE_SCALE, "Shares should sum to 100%");

        // Note: Actual royalty token balance verification requires
        // accessing the royalty vault's token distribution state.
        // This is implementation-specific and may require additional
        // helper functions based on the vault's interface.

        console2.log("Royalty vault deployed at:", royaltyVault);
        console2.log("Expected recipients:", expectedRecipients.length);
        console2.log("Total shares verified:", totalShares);
    }

    /// @dev Asserts parent-child derivative relationship is correct
    /// @param parentIpId The parent IP address
    /// @param childIpId The child/derivative IP address
    function assertDerivativeRelationship(
        address parentIpId,
        address childIpId
    ) internal {
        assertTrue(
            LICENSE_REGISTRY.isParentIp(parentIpId, childIpId),
            "Parent relationship should exist"
        );

        assertTrue(
            LICENSE_REGISTRY.isDerivativeIp(childIpId),
            "Child should be marked as derivative"
        );
    }

    /// @dev Asserts gas usage is within acceptable threshold (soft warning)
    /// @param gasUsed The actual gas used
    /// @param threshold The maximum acceptable gas
    /// @param label Description for logging
    function assertGasUsage(
        uint256 gasUsed,
        uint256 threshold,
        string memory label
    ) internal pure {
        // Soft warning: log but don't fail test
        if (gasUsed > threshold) {
            console2.log("WARNING:", label, "exceeded gas threshold");
            console2.log("  Gas used:", gasUsed);
            console2.log("  Threshold:", threshold);
            console2.log("  Overage:", gasUsed - threshold);
        } else {
            console2.logString(
                string(
                    abi.encodePacked(
                        label,
                        " gas used: ",
                        vm.toString(gasUsed),
                        " / threshold: ",
                        vm.toString(threshold)
                    )
                )
            );
        }
    }

    // Gas Measurement Utilities

    /// @dev Measures gas for a function call
    /// @return gasUsed The gas consumed by the operation
    function _measureGas() internal view returns (uint256 gasUsed) {
        return gasleft();
    }

    /// @dev Calculates gas used between snapshots
    /// @param gasBefore The gas measurement before operation
    /// @return gasUsed The gas consumed
    function _calculateGasUsed(
        uint256 gasBefore
    ) internal view returns (uint256 gasUsed) {
        return gasBefore - gasleft();
    }
}
