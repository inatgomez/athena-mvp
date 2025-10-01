// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

// Story Protocol Test Utilities
import {MockIPGraph} from "@storyprotocol/test/mocks/MockIPGraph.sol";
import {MockERC20} from "@storyprotocol/test/mocks/token/MockERC20.sol";

// Story Protocol Core Interfaces
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {ILicenseRegistry} from "@storyprotocol/core/interfaces/registries/ILicenseRegistry.sol";
import {IPILicenseTemplate} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import {IRoyaltyModule} from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";

// Story Protocol Periphery Interfaces
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {IRoyaltyTokenDistributionWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {IRoyaltyWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";

// Contract under test
import {BookIPRegistrationAndManagement} from "../src/BookIPRegistrationAndManagement.sol";

/// @title Book IP Management Test Suite
/// @notice Comprehensive tests for book registration, derivative creation, and end-to-end workflows
/// @dev Run with: forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/BookIPManagement.t.sol -vvv
contract BookIPManagementTest is Test {
    // ============ TEST ACCOUNTS ============
    address internal owner = address(0x999999);
    address internal alice = address(0xa11ce); // Author 1
    address internal bob = address(0xb0b); // Author 2 / Derivative creator
    address internal carol = address(0xca501); // Tipper / Reader
    address internal dave = address(0xda4e); // Additional collaborator
    address internal unauthorized = address(0xbad);

    // ============ STORY PROTOCOL CORE CONTRACTS ============
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

    // ============ STORY PROTOCOL PERIPHERY CONTRACTS ============
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

    // ============ PROTOCOL CONSTANTS ============
    address internal constant ROYALTY_POLICY_LAP =
        0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;
    address internal constant MERC20_ADDRESS =
        0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E;
    MockERC20 internal MERC20 = MockERC20(MERC20_ADDRESS);

    // Story Protocol percentage scale (100_000_000 = 100%)
    uint32 internal constant PERCENTAGE_SCALE = 100_000_000;

    // ============ CONTRACT UNDER TEST ============
    BookIPRegistrationAndManagement internal bookContract;

    // ============ TEST STATE ============
    address internal spgNftCollection;

    // ============ SETUP ============

    function setUp() public {
        // Deploy MockIPGraph for fork testing (required for license attachment)
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

        // Authorize alice and bob as authors
        vm.startPrank(owner);
        bookContract.setAuthorized(alice, true);
        bookContract.setAuthorized(bob, true);
        vm.stopPrank();

        // Fund test accounts with MERC20 tokens
        MERC20.mint(alice, 10000 * 10 ** 18);
        MERC20.mint(bob, 10000 * 10 ** 18);
        MERC20.mint(carol, 10000 * 10 ** 18);
        MERC20.mint(dave, 10000 * 10 ** 18);

        // Approve periphery contracts for derivative minting fees
        vm.prank(alice);
        MERC20.approve(
            address(ROYALTY_DISTRIBUTION_WORKFLOWS),
            type(uint256).max
        );
        vm.prank(bob);
        MERC20.approve(
            address(ROYALTY_DISTRIBUTION_WORKFLOWS),
            type(uint256).max
        );
        vm.prank(carol);
        MERC20.approve(
            address(ROYALTY_DISTRIBUTION_WORKFLOWS),
            type(uint256).max
        );

        // Approve bookContract for tips
        vm.prank(carol);
        MERC20.approve(address(bookContract), type(uint256).max);
        vm.prank(bob);
        MERC20.approve(address(bookContract), type(uint256).max);
    }

    // ============ HELPER FUNCTIONS ============

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

    /// @dev Creates standard book metadata
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

    /// @dev Helper to build claim revenue data
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

    // ============================================================
    //                   COLLECTION & AUTHORIZATION TESTS
    // ============================================================

    function test_CreateBookCollection_Success() public {
        // Deploy new contract without collection
        BookIPRegistrationAndManagement newContract = new BookIPRegistrationAndManagement(
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

        vm.prank(owner);
        newContract.createBookCollection(_getCollectionInitParams());

        address collection = newContract.spgNftCollection();
        assertTrue(collection != address(0), "Collection should be created");
    }

    function test_CreateBookCollection_RevertWhen_AlreadyCreated() public {
        vm.prank(owner);
        vm.expectRevert(
            BookIPRegistrationAndManagement.CollectionAlreadyCreated.selector
        );
        bookContract.createBookCollection(_getCollectionInitParams());
    }

    function test_CreateBookCollection_RevertWhen_NotOwner() public {
        BookIPRegistrationAndManagement newContract = new BookIPRegistrationAndManagement(
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

        vm.prank(alice);
        vm.expectRevert();
        newContract.createBookCollection(_getCollectionInitParams());
    }

    function test_SetAuthorized_Success() public {
        assertFalse(
            bookContract.authorizedAuthors(dave),
            "Dave should not be authorized initially"
        );

        vm.prank(owner);
        bookContract.setAuthorized(dave, true);

        assertTrue(
            bookContract.authorizedAuthors(dave),
            "Dave should be authorized"
        );

        vm.prank(owner);
        bookContract.setAuthorized(dave, false);

        assertFalse(
            bookContract.authorizedAuthors(dave),
            "Dave should be deauthorized"
        );
    }

    function test_SetAuthorized_RevertWhen_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        bookContract.setAuthorized(dave, true);
    }

    // ============================================================
    //                   BOOK REGISTRATION TESTS
    // ============================================================

    function test_RegisterBook_SingleAuthor_CommercialLicense() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Alice-Adventures"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 0; // Commercial Remix

        uint256 gasBefore = gasleft();

        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice, // recipient
                metadata, // IP metadata
                licenseTypes, // Commercial license
                10 * 10 ** 18, // 10 MERC20 fee
                5_000_000, // 5% royalty
                new WorkflowStructs.RoyaltyShare[](0), // Empty (use authors array)
                _toAddressArray(alice), // Single author
                new uint256[](0), // Empty (single author)
                false // No duplicates
            );

        uint256 gasUsed = gasBefore - gasleft();

        // Verify registration
        assertTrue(ipId != address(0), "IP should be registered");
        assertTrue(
            IP_ASSET_REGISTRY.isRegistered(ipId),
            "IP should be in registry"
        );

        // Verify NFT ownership
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(tokenId),
            alice,
            "Alice should own NFT"
        );

        // Verify license attachment
        assertEq(licenseTermsIds.length, 1, "Should have 1 license");
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsIds[0]
            ),
            "License should be attached"
        );

        // Verify royalty vault deployment
        address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
        assertTrue(
            royaltyVault != address(0),
            "Royalty vault should be deployed"
        );

        // Gas assertion (acceptable threshold for complex operation)
        assertLt(gasUsed, 500_000, "Gas usage should be under 500K");
        console2.log("Gas used for single author book registration:", gasUsed);
    }

    function test_RegisterBook_SingleAuthor_NonCommercialLicense() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "NonCommercial-Work"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1; // Non-Commercial Social Remixing

        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice,
                metadata,
                licenseTypes,
                0, // No commercial fee
                0, // No commercial royalty
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        assertTrue(IP_ASSET_REGISTRY.isRegistered(ipId));
        assertEq(ISPGNFT(spgNftCollection).ownerOf(tokenId), alice);
        assertEq(licenseTermsIds.length, 1);
    }

    function test_RegisterBook_MultipleAuthors_SplitRoyalties() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Collaborative-Novel"
        );
        uint8[] memory licenseTypes = new uint8[](2);
        licenseTypes[0] = 0; // Commercial
        licenseTypes[1] = 1; // Non-Commercial

        address[] memory authors = new address[](2);
        authors[0] = alice;
        authors[1] = bob;

        uint256[] memory authorShares = new uint256[](2);
        authorShares[0] = 60_000_000; // Alice 60%
        authorShares[1] = 40_000_000; // Bob 40%

        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice, // Recipient (first author manages NFT)
                metadata,
                licenseTypes,
                5 * 10 ** 18, // 5 MERC20 fee
                10_000_000, // 10% royalty
                new WorkflowStructs.RoyaltyShare[](0), // Empty for multi-author
                authors,
                authorShares,
                false
            );

        assertTrue(IP_ASSET_REGISTRY.isRegistered(ipId));
        assertEq(licenseTermsIds.length, 2, "Should have 2 license types");

        // Verify both licenses attached
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsIds[0]
            )
        );
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsIds[1]
            )
        );
    }

    function test_RegisterBook_VerifyNFTOwnership() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Ownership-Test"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;

        vm.prank(alice);
        (address ipId, uint256 tokenId, ) = bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Verify NFT owner matches recipient
        address nftOwner = ISPGNFT(spgNftCollection).ownerOf(tokenId);
        assertEq(nftOwner, alice, "NFT owner should be alice");
    }

    function test_RegisterBook_VerifyIPRegistration() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "IP-Registry-Test"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;

        vm.prank(alice);
        (address ipId, , ) = bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Verify IP is registered in protocol
        assertTrue(
            IP_ASSET_REGISTRY.isRegistered(ipId),
            "IP should be registered"
        );

        // Verify IP metadata
        address registeredIp = IP_ASSET_REGISTRY.ipId(
            block.chainid,
            spgNftCollection,
            1
        );
        assertEq(registeredIp, ipId, "IP ID should match");
    }

    function test_RegisterBook_VerifyLicenseAttachment() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "License-Attachment-Test"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 0; // Commercial

        vm.prank(alice);
        (address ipId, , uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice,
                metadata,
                licenseTypes,
                10 * 10 ** 18,
                5_000_000,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Verify license count
        uint256 licenseCount = LICENSE_REGISTRY.getAttachedLicenseTermsCount(
            ipId
        );
        assertEq(licenseCount, 1, "Should have 1 attached license");

        // Verify specific license is attached
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsIds[0]
            ),
            "Commercial license should be attached"
        );
    }

    function test_RegisterBook_VerifyRoyaltyVaultDeployment() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Royalty-Vault-Test"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 0;

        vm.prank(alice);
        (address ipId, , ) = bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            10 * 10 ** 18,
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Verify royalty vault is deployed
        address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
        assertTrue(royaltyVault != address(0), "Royalty vault should exist");

        // Verify vault is a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(royaltyVault)
        }
        assertTrue(codeSize > 0, "Royalty vault should be a contract");
    }

    function test_RegisterBook_RevertWhen_Unauthorized() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Unauthorized-Book"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;

        vm.prank(unauthorized);
        vm.expectRevert(BookIPRegistrationAndManagement.Unauthorized.selector);
        bookContract.registerBook(
            unauthorized,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(unauthorized),
            new uint256[](0),
            false
        );
    }

    function test_RegisterBook_RevertWhen_InvalidLicenseTypes() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-License"
        );
        uint8[] memory invalidLicenseTypes = new uint8[](1);
        invalidLicenseTypes[0] = 5; // Invalid (only 0-2 allowed)

        vm.prank(alice);
        vm.expectRevert(
            BookIPRegistrationAndManagement.InvalidLicenseTypes.selector
        );
        bookContract.registerBook(
            alice,
            metadata,
            invalidLicenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );
    }

    function test_RegisterBook_RevertWhen_InvalidRoyaltyShares() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-Shares"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;

        address[] memory authors = new address[](2);
        authors[0] = alice;
        authors[1] = bob;

        uint256[] memory invalidShares = new uint256[](2);
        invalidShares[0] = 50_000_000; // 50%
        invalidShares[1] = 30_000_000; // 30% (total = 80%, not 100%)

        vm.prank(alice);
        vm.expectRevert(
            BookIPRegistrationAndManagement.InvalidRoyaltyShares.selector
        );
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            authors,
            invalidShares,
            false
        );
    }

    function test_RegisterBook_EmitsCorrectEvents() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Event-Test"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;

        vm.prank(alice);

        // We can't predict exact values, but we can check event is emitted
        vm.recordLogs();

        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Check that BookRegistered event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventFound = false;

        for (uint i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] ==
                keccak256(
                    "BookRegistered(address,uint256,uint256[],address,uint256)"
                )
            ) {
                eventFound = true;
                break;
            }
        }

        assertTrue(eventFound, "BookRegistered event should be emitted");
    }

    function test_RegisterBook_GasUsage() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Gas-Benchmark"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 0;

        vm.prank(alice);

        uint256 gasBefore = gasleft();
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            10 * 10 ** 18,
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );
        uint256 gasUsed = gasBefore - gasleft();

        // Acceptable threshold for complex registration
        assertLt(gasUsed, 500_000, "Gas should be under 500K");
        console2.log("Book registration gas usage:", gasUsed);
    }

    // ============================================================
    //                   DERIVATIVE CREATION TESTS
    // ============================================================

    function test_RegisterDerivative_SingleParent_ZeroFee() public {
        // Create parent book with non-commercial license (zero fee)
        vm.prank(alice);
        (address parentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Parent-Book"),
            _toUint8Array(1), // Non-commercial
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Get parent's license terms
        uint256 parentLicenseTermsId = LICENSE_REGISTRY.getAttachedLicenseTerms(
            parentIpId,
            address(PIL_TEMPLATE),
            0
        );

        uint256 gasBefore = gasleft();

        // Bob creates derivative
        vm.prank(bob);
        (address derivativeIpId, uint256 derivativeTokenId) = bookContract
            .registerDerivative(
                bob, // recipient
                _toAddressArray(parentIpId), // parent IPs
                _toUint256Array(parentLicenseTermsId), // license terms
                _createBookMetadata("Derivative-Work"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob), // single author
                new uint256[](0),
                0, // maxMintingFee (zero for non-commercial)
                0, // maxRts
                0, // maxRevenueShare
                false
            );

        uint256 gasUsed = gasBefore - gasleft();

        // Verify derivative registration
        assertTrue(
            IP_ASSET_REGISTRY.isRegistered(derivativeIpId),
            "Derivative should be registered"
        );
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(derivativeTokenId),
            bob,
            "Bob should own derivative NFT"
        );

        // Verify parent-child relationship
        assertTrue(
            LICENSE_REGISTRY.isParentIp(parentIpId, derivativeIpId),
            "Parent relationship should exist"
        );
        assertTrue(
            LICENSE_REGISTRY.isDerivativeIp(derivativeIpId),
            "Should be marked as derivative"
        );

        // Gas assertion
        assertLt(gasUsed, 400_000, "Gas should be under 400K");
        console2.log("Derivative creation gas (zero fee):", gasUsed);
    }

    function test_RegisterDerivative_SingleParent_WithCommercialFee() public {
        // Create parent book with commercial license
        vm.prank(alice);
        (address parentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Commercial-Parent"),
            _toUint8Array(0), // Commercial
            10 * 10 ** 18, // 10 MERC20 fee
            5_000_000, // 5% royalty
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        uint256 parentLicenseTermsId = LICENSE_REGISTRY.getAttachedLicenseTerms(
            parentIpId,
            address(PIL_TEMPLATE),
            0
        );

        // Bob creates derivative (must pay minting fee)
        vm.prank(bob);
        (address derivativeIpId, uint256 derivativeTokenId) = bookContract
            .registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(parentLicenseTermsId),
                _createBookMetadata("Commercial-Derivative"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                20 * 10 ** 18, // maxMintingFee (willing to pay up to 20 MERC20)
                0,
                0,
                false
            );

        // Verify derivative creation
        assertTrue(IP_ASSET_REGISTRY.isRegistered(derivativeIpId));
        assertEq(ISPGNFT(spgNftCollection).ownerOf(derivativeTokenId), bob);
        assertTrue(LICENSE_REGISTRY.isParentIp(parentIpId, derivativeIpId));
    }

    function test_RegisterDerivative_MultipleParents_AllCommercial() public {
        // Create two parent books with commercial licenses
        vm.prank(alice);
        (address parent1IpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Parent-1"),
            _toUint8Array(0),
            10 * 10 ** 18,
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        vm.prank(bob);
        (address parent2IpId, , ) = bookContract.registerBook(
            bob,
            _createBookMetadata("Parent-2"),
            _toUint8Array(0),
            10 * 10 ** 18,
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            false
        );

        uint256 parent1LicenseTermsId = LICENSE_REGISTRY
            .getAttachedLicenseTerms(parent1IpId, address(PIL_TEMPLATE), 0);
        uint256 parent2LicenseTermsId = LICENSE_REGISTRY
            .getAttachedLicenseTerms(parent2IpId, address(PIL_TEMPLATE), 0);

        address[] memory parentIpIds = new address[](2);
        parentIpIds[0] = parent1IpId;
        parentIpIds[1] = parent2IpId;

        uint256[] memory licenseTermsIds = new uint256[](2);
        licenseTermsIds[0] = parent1LicenseTermsId;
        licenseTermsIds[1] = parent2LicenseTermsId;

        // Carol creates derivative from both parents
        vm.prank(carol);
        (address derivativeIpId, uint256 derivativeTokenId) = bookContract
            .registerDerivative(
                carol,
                parentIpIds,
                licenseTermsIds,
                _createBookMetadata("Multi-Parent-Derivative"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(carol),
                new uint256[](0),
                50 * 10 ** 18, // Max fee for both parents
                0,
                0,
                false
            );

        // Verify derivative has both parents
        assertTrue(
            LICENSE_REGISTRY.isParentIp(parent1IpId, derivativeIpId),
            "Parent 1 relationship"
        );
        assertTrue(
            LICENSE_REGISTRY.isParentIp(parent2IpId, derivativeIpId),
            "Parent 2 relationship"
        );
        assertEq(
            LICENSE_REGISTRY.getParentIpCount(derivativeIpId),
            2,
            "Should have 2 parents"
        );
    }

    function test_RegisterDerivative_VerifyNFTOwnershipTransfer() public {
        // Create parent
        vm.prank(alice);
        (address parentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Parent-Ownership-Test"),
            _toUint8Array(1),
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        uint256 parentLicenseTermsId = LICENSE_REGISTRY.getAttachedLicenseTerms(
            parentIpId,
            address(PIL_TEMPLATE),
            0
        );

        // Bob creates derivative
        vm.prank(bob);
        (address derivativeIpId, uint256 derivativeTokenId) = bookContract
            .registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(parentLicenseTermsId),
                _createBookMetadata("Derivative-Ownership-Test"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                0,
                0,
                0,
                false
            );

        // Verify NFT transfer happened
        address nftOwner = ISPGNFT(spgNftCollection).ownerOf(derivativeTokenId);
        assertEq(nftOwner, bob, "Bob should own derivative NFT");

        // Verify IP owner matches NFT owner
        address ipOwner = IP_ASSET_REGISTRY.ipAccountOwner(derivativeIpId);
        assertEq(ipOwner, bob, "IP owner should match NFT owner");
    }

    function test_RegisterDerivative_VerifyLicenseInheritance() public {
        // Create parent with multiple license types
        uint8[] memory parentLicenseTypes = new uint8[](2);
        parentLicenseTypes[0] = 0; // Commercial
        parentLicenseTypes[1] = 1; // Non-commercial

        vm.prank(alice);
        (
            address parentIpId,
            ,
            uint256[] memory parentLicenseTermsIds
        ) = bookContract.registerBook(
                alice,
                _createBookMetadata("Multi-License-Parent"),
                parentLicenseTypes,
                10 * 10 ** 18,
                5_000_000,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Bob creates derivative using first license term
        vm.prank(bob);
        (address derivativeIpId, ) = bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsIds[0]),
            _createBookMetadata("Inherited-License-Derivative"),
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            20 * 10 ** 18,
            0,
            0,
            false
        );

        // Shallow verification: check derivative has inherited licenses
        uint256 derivativeLicenseCount = LICENSE_REGISTRY
            .getAttachedLicenseTermsCount(derivativeIpId);
        assertTrue(
            derivativeLicenseCount > 0,
            "Derivative should have inherited licenses"
        );
    }

    function test_RegisterDerivative_GasUsage() public {
        // Create parent
        vm.prank(alice);
        (address parentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Gas-Parent"),
            _toUint8Array(1),
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        uint256 parentLicenseTermsId = LICENSE_REGISTRY.getAttachedLicenseTerms(
            parentIpId,
            address(PIL_TEMPLATE),
            0
        );

        vm.prank(bob);
        uint256 gasBefore = gasleft();

        bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            _createBookMetadata("Gas-Derivative"),
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            0,
            0,
            0,
            false
        );

        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 400_000, "Derivative gas should be under 400K");
        console2.log("Derivative creation gas usage:", gasUsed);
    }

    function test_RegisterDerivative_RevertWhen_IncompatibleLicenses() public {
        // Create parent with commercial license
        vm.prank(alice);
        (address commercialParentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Commercial-Parent-Incompatible"),
            _toUint8Array(0), // Commercial
            10 * 10 ** 18,
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        // Create parent with non-commercial license
        vm.prank(bob);
        (address nonCommercialParentIpId, , ) = bookContract.registerBook(
            bob,
            _createBookMetadata("NonCommercial-Parent-Incompatible"),
            _toUint8Array(1), // Non-commercial
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            false
        );

        uint256 commercialLicenseTermsId = LICENSE_REGISTRY
            .getAttachedLicenseTerms(
                commercialParentIpId,
                address(PIL_TEMPLATE),
                0
            );
        uint256 nonCommercialLicenseTermsId = LICENSE_REGISTRY
            .getAttachedLicenseTerms(
                nonCommercialParentIpId,
                address(PIL_TEMPLATE),
                0
            );

        address[] memory incompatibleParents = new address[](2);
        incompatibleParents[0] = commercialParentIpId;
        incompatibleParents[1] = nonCommercialParentIpId;

        uint256[] memory incompatibleLicenses = new uint256[](2);
        incompatibleLicenses[0] = commercialLicenseTermsId;
        incompatibleLicenses[1] = nonCommercialLicenseTermsId;

        // Protocol should reject incompatible licenses (commercial + non-commercial)
        vm.prank(carol);
        vm.expectRevert(); // Protocol will revert with its own error
        bookContract.registerDerivative(
            carol,
            incompatibleParents,
            incompatibleLicenses,
            _createBookMetadata("Incompatible-Derivative"),
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(carol),
            new uint256[](0),
            50 * 10 ** 18,
            0,
            0,
            false
        );
    }

    function test_RegisterDerivative_RevertWhen_InsufficientPayment() public {
        // Create parent with high minting fee
        vm.prank(alice);
        (address parentIpId, , ) = bookContract.registerBook(
            alice,
            _createBookMetadata("Expensive-Parent"),
            _toUint8Array(0),
            100 * 10 ** 18, // High fee
            5_000_000,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(alice),
            new uint256[](0),
            false
        );

        uint256 parentLicenseTermsId = LICENSE_REGISTRY.getAttachedLicenseTerms(
            parentIpId,
            address(PIL_TEMPLATE),
            0
        );

        // Bob tries to create derivative with insufficient maxMintingFee
        vm.prank(bob);
        vm.expectRevert(); // Protocol will revert when actual fee exceeds max
        bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            _createBookMetadata("Underfunded-Derivative"),
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            50 * 10 ** 18, // Too low (fee is 100)
            0,
            0,
            false
        );
    }

    function test_RegisterDerivative_RevertWhen_TooManyParents() public {
        // Attempt to create derivative with 17 parents (exceeds MAX_COLLABORATORS = 16)
        address[] memory tooManyParents = new address[](17);
        uint256[] memory licenseTermsIds = new uint256[](17);

        for (uint i = 0; i < 17; i++) {
            tooManyParents[i] = address(uint160(i + 1));
            licenseTermsIds[i] = 1;
        }

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                BookIPRegistrationAndManagement.TooManyCollaborators.selector,
                17,
                16
            )
        );
        bookContract.registerDerivative(
            bob,
            tooManyParents,
            licenseTermsIds,
            _createBookMetadata("Too-Many-Parents"),
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            0,
            0,
            0,
            false
        );
    }

    // ============================================================
    //                   END-TO-END INTEGRATION TEST
    // ============================================================

    /// @notice Complete royalty flow: book registration → derivative creation → tip → royalty payment → claims
    function test_EndToEnd_CompleteRoyaltyFlow() public {
        console2.log("\n=== PHASE 1: BOOK REGISTRATION ===");

        // Alice registers a book with commercial license
        vm.prank(alice);
        (
            address bookIpId,
            uint256 bookTokenId,
            uint256[] memory bookLicenseTermsIds
        ) = bookContract.registerBook(
                alice,
                _createBookMetadata("Original-Novel"),
                _toUint8Array(0), // Commercial
                10 * 10 ** 18, // 10 MERC20 minting fee
                5_000_000, // 5% royalty share
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Verify book registration
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(bookTokenId),
            alice,
            "Alice owns book NFT"
        );
        assertTrue(
            IP_ASSET_REGISTRY.isRegistered(bookIpId),
            "Book IP registered"
        );
        address bookRoyaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(bookIpId);
        assertTrue(
            bookRoyaltyVault != address(0),
            "Book royalty vault deployed"
        );

        console2.log("Book IP ID:", bookIpId);
        console2.log("Book Token ID:", bookTokenId);
        console2.log("Book Royalty Vault:", bookRoyaltyVault);

        // ========== PHASE 2: DERIVATIVE CREATION ==========
        console2.log("\n=== PHASE 2: DERIVATIVE CREATION ===");

        // Bob creates a derivative (fanfiction) with commercial license inherited
        vm.prank(bob);
        (address derivativeIpId, uint256 derivativeTokenId) = bookContract
            .registerDerivative(
                bob,
                _toAddressArray(bookIpId),
                _toUint256Array(bookLicenseTermsIds[0]),
                _createBookMetadata("Fanfiction-Sequel"),
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                20 * 10 ** 18, // Willing to pay up to 20 MERC20
                0,
                0,
                false
            );

        // Verify derivative creation
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(derivativeTokenId),
            bob,
            "Bob owns derivative NFT"
        );
        assertTrue(
            LICENSE_REGISTRY.isParentIp(bookIpId, derivativeIpId),
            "Parent-child relationship"
        );
        address derivativeRoyaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(
            derivativeIpId
        );
        assertTrue(
            derivativeRoyaltyVault != address(0),
            "Derivative royalty vault deployed"
        );

        console2.log("Derivative IP ID:", derivativeIpId);
        console2.log("Derivative Token ID:", derivativeTokenId);
        console2.log("Derivative Royalty Vault:", derivativeRoyaltyVault);

        // ========== PHASE 3: TIP PAYMENT ==========
        console2.log("\n=== PHASE 3: TIP PAYMENT ===");

        uint256 tipAmount = 100 * 10 ** 18; // 100 MERC20
        uint256 carolBalanceBefore = MERC20.balanceOf(carol);
        uint256 derivativeBalanceBefore = MERC20.balanceOf(derivativeIpId);

        // Carol tips Bob's derivative
        vm.prank(carol);
        bookContract.payTip(
            derivativeIpId,
            tipAmount,
            "Amazing fanfic!",
            type(uint256).max
        );

        // Verify tip payment
        uint256 appRoyaltyFeePercent = bookContract.appRoyaltyFeePercent();
        uint256 expectedAppFee = (tipAmount * appRoyaltyFeePercent) /
            PERCENTAGE_SCALE;
        uint256 expectedTipAmount = tipAmount - expectedAppFee;

        assertEq(
            MERC20.balanceOf(derivativeIpId),
            derivativeBalanceBefore + expectedTipAmount,
            "Derivative received tip"
        );
        assertEq(
            MERC20.balanceOf(address(bookContract)),
            expectedAppFee,
            "Platform fee collected"
        );

        console2.log("Tip amount:", tipAmount);
        console2.log("Platform fee:", expectedAppFee);
        console2.log("Derivative received:", expectedTipAmount);

        // ========== PHASE 4: ROYALTY SHARE PAYMENT ==========
        console2.log("\n=== PHASE 4: ROYALTY SHARE PAYMENT ===");

        uint256 royaltyPayment = 50 * 10 ** 18; // Bob pays 50 MERC20 to Alice's book

        // Bob pays royalty share to Alice's book
        vm.prank(bob);
        bookContract.payRoyaltyShare(
            bookIpId,
            derivativeIpId,
            royaltyPayment,
            "Quarterly royalties from fanfiction"
        );

        console2.log("Royalty payment to book:", royaltyPayment);

        // ========== PHASE 5: ROYALTY CLAIMS ==========
        console2.log("\n=== PHASE 5: ROYALTY CLAIMS ===");

        // Alice claims royalties from her book
        WorkflowStructs.ClaimRevenueData[]
            memory aliceClaimData = _buildClaimData(
                derivativeIpId,
                ROYALTY_POLICY_LAP,
                MERC20_ADDRESS
            );

        uint256 aliceBalanceBefore = MERC20.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory aliceAmounts = bookContract.claimRoyalties(
            bookIpId,
            alice,
            aliceClaimData
        );

        uint256 aliceBalanceAfter = MERC20.balanceOf(alice);
        uint256 aliceClaimed = aliceBalanceAfter - aliceBalanceBefore;

        console2.log("Alice claimed from book:", aliceClaimed);
        assertTrue(
            aliceClaimed > 0,
            "Alice should receive royalties from derivative"
        );

        // Bob claims royalties from his derivative (the tip he received)
        // Note: Tips go directly to IP account, so Bob just needs to claim from vault
        uint256 bobBalanceBefore = MERC20.balanceOf(bob);

        // For tips that went to IP account, we need to claim from the vault
        // This is a simplified claim - in production you'd have more complex revenue sources
        vm.prank(bob);
        uint256[] memory bobAmounts = bookContract.claimRoyalties(
            derivativeIpId,
            bob,
            new WorkflowStructs.ClaimRevenueData[](0) // No child IPs to claim from
        );

        console2.log("Bob's claim amounts length:", bobAmounts.length);

        // ========== FINAL ASSERTIONS ==========
        console2.log("\n=== FINAL VERIFICATION ===");

        // Verify Alice received royalties from Bob's derivative
        assertTrue(
            aliceClaimed > 0,
            "Alice earned royalties as parent IP owner"
        );

        // Verify parent-child relationship persists
        assertTrue(
            LICENSE_REGISTRY.isDerivativeIp(derivativeIpId),
            "Derivative status maintained"
        );
        assertTrue(
            LICENSE_REGISTRY.isParentIp(bookIpId, derivativeIpId),
            "Parent relationship maintained"
        );

        // Verify ownership hasn't changed
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(bookTokenId),
            alice,
            "Alice still owns book"
        );
        assertEq(
            ISPGNFT(spgNftCollection).ownerOf(derivativeTokenId),
            bob,
            "Bob still owns derivative"
        );

        console2.log("\n=== END-TO-END TEST COMPLETE ===");
    }

    // ============================================================
    //                   UTILITY FUNCTIONS
    // ============================================================

    /// @dev Converts single address to address array
    function _toAddressArray(
        address addr
    ) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /// @dev Converts single uint8 to uint8 array
    function _toUint8Array(uint8 val) internal pure returns (uint8[] memory) {
        uint8[] memory arr = new uint8[](1);
        arr[0] = val;
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
}
