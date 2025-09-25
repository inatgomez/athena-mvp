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

// Run this test
// forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/BookRegistrationTest.t.sol -vvvv

contract BookRegistrationTest is Test {
    // Test accounts
    address internal owner = address(0x0431);
    address internal alice = address(0xa11ce);
    address internal bob = address(0xb0b);
    address internal carol = address(0xca501);
    address internal unauthorized = address(0xbad);

    // Story Protocol core addresses (Testnet)

    IIPAssetRegistry internal constant IP_ASSET_REGISTRY =
        IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    ILicenseRegistry internal constant LICENSE_REGISTRY =
        ILicenseRegistry(0x529a750E02d8E2f15649c13D69a465286a780e24);
    IPILicenseTemplate internal constant PIL_TEMPLATE =
        IPILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    IRoyaltyModule internal constant ROYALTY_MODULE =
        IRoyaltyModule(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);

    // Story Protocol Periphery Addresses
    IRegistrationWorkflows internal constant REGISTRATION_WORKFLOWS =
        IRegistrationWorkflows(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    IRoyaltyTokenDistributionWorkflows
        internal constant ROYALTY_DISTRIBUTION_WORKFLOWS =
        IRoyaltyTokenDistributionWorkflows(
            0x77319B4031e6eF1250907aa00018B8B1c67a244b
        );
    IDerivativeWorkflows internal constant DERIVATIVE_WORKFLOWS =
        IDerivativeWorkflows(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    IRoyaltyWorkflows internal constant ROYALTY_WORKFLOWS =
        IRoyaltyWorkflows(0x77319B4031e6eF1250907aa00018B8B1c67a244b);

    // Protocol Constants
    address internal constant ROYALTY_POLICY_LAP =
        0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;
    address internal constant MERC20 =
        0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E;

    // Contract under test
    BookIPRegistrationAndManagement internal bookContract;
    MockERC20 internal mockToken;

    function setUp() public {
        // Deploy MockIPGraph for fork testing
        vm.etch(address(0x0101), address(new MockIPGraph()).code);

        // Deploy our contract
        bookContract = new BookIPRegistrationAndManagement(
            owner,
            address(REGISTRATION_WORKFLOWS),
            address(ROYALTY_DISTRIBUTION_WORKFLOWS),
            address(DERIVATIVE_WORKFLOWS),
            address(ROYALTY_WORKFLOWS),
            address(ROYALTY_MODULE),
            address(PIL_TEMPLATE),
            MERC20,
            ROYALTY_POLICY_LAP
        );

        // Setup mock token for payments
        mockToken = MockERC20(MERC20);

        // Fund test accounts
        mockToken.mint(carol, 100);
        vm.prank(carol);
        mockToken.approve(address(bookContract), type(uint256).max);

        // Create NFT collection
        vm.prank(owner);
        _createBookCollection();

        // Authorize Alice as an author
        vm.prank(owner);
        bookContract.setAuthorized(alice, true);
    }

    /// @notice Creates the SPGNFT collection for testing
    function _createBookCollection() internal {
        ISPGNFT.InitParams memory initParams = ISPGNFT.InitParams({
            name: "Athena Test Books Collection",
            symbol: "ATHENATEST",
            baseURI: "https://ipfs.io/ipfs/",
            contractURI: "",
            maxSupply: 10000,
            mintFee: 0,
            mintFeeToken: address(0),
            mintFeeRecipient: address(0),
            owner: address(bookContract),
            mintOpen: true,
            isPublicMinting: false
        });

        bookContract.createBookCollection(initParams);
    }

    // @notice Helper to create standard book metadata
    function _createBookMetadata(
        string memory title
    ) internal pure returns (WorkflowStructs.IPMetadata memory) {
        return
            WorkflowStructs.IPMetadata({
                ipMetadataURI: string(abi.encodePacked("ipfs://book-", title)),
                ipMetadataHash: bytes32(0),
                nftMetadataURI: string(abi.encodePacked("ipfs://nft-", title)),
                nftMetadataHash: bytes32(0)
            });
    }

    /// @notice Helper to create standard royalty shares for single author
    function _createSingleAuthorRoyalty(
        address author
    ) internal pure returns (WorkflowStructs.RoyaltyShare[] memory) {
        WorkflowStructs.RoyaltyShare[]
            memory shares = new WorkflowStructs.RoyaltyShare[](1);
        shares[0] = WorkflowStructs.RoyaltyShare({
            recipient: author,
            percentage: 100_000_000 // 100% in Story format
        });
        return shares;
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ContractDeployment() public {
        // Verify contract is properly deployed with parameters
        assertEq(bookContract.owner(), owner);
        assertEq(
            address(bookContract.registrationWorkflows()),
            address(REGISTRATION_WORKFLOWS)
        );
        assertEq(bookContract.pilTemplate(), address(PIL_TEMPLATE));
        assertEq(bookContract.supportedCurrency(), MERC20);
        assertEq(bookContract.royaltyPolicyAddress(), ROYALTY_POLICY_LAP);
        assertEq(bookContract.appRoyaltyFeePercent(), 1_000); // 0.1%
    }

    function test_BookCollectionCreation() public {
        // Collection should be created in setUp
        assertTrue(bookContract.spgNftCollection() != address(0));

        // Should not be able to create collection twice
        vm.prank(owner);
        vm.expectRevert("Collection already created");
        _createBookCollection();
    }

    function test_AuthorAuthorization() public {
        // Alice should be authorized from setUp
        assertTrue(bookContract.authorizedAuthors(alice));
        assertFalse(bookContract.authorizedAuthors(bob));

        // Owner can authorize new authors
        vm.prank(owner);
        bookContract.setAuthorized(bob, true);
        assertTrue(bookContract.authorizedAuthors(bob));

        // Owner can revoke authorization
        vm.prank(owner);
        bookContract.setAuthorized(bob, false);
        assertFalse(bookContract.authorizedAuthors(bob));

        // Non-owner cannot authorize
        vm.prank(alice);
        vm.expectRevert();
        bookContract.setAuthorized(bob, true);
    }

    /*//////////////////////////////////////////////////////////////
                        BOOK REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterBook_SingleAuthor_CommercialLicense() public {
        // Setup test data
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Alice-Adventures"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 0; // Commercial Remix
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(alice);
        address[] memory authors = new address[](0); // Empty for single author
        uint256[] memory authorShares = new uint256[](0);

        // Register the book
        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice, // recipient
                metadata, // IP metadata
                licenseTypes, // Commercial only
                10, // Custom commercial fee
                5_000_000, // 5% royalty share
                royaltyShares, // Royalty distribution
                authors, // No co-authors
                authorShares, // No co-author shares
                false // No duplicate metadata
            );

        // Verify IP was registered
        assertTrue(ipId != address(0));
        assertTrue(IP_ASSET_REGISTRY.isRegistered(ipId));

        // Verify author is owner of NFT
        // assertEq(spgNftCollection.ownerOf(tokenId), alice);

        // Verify license terms were attached
        assertEq(licenseTermsIds.length, 1);
        assertTrue(
            LICENSE_REGISTRY.hasIpAttachedLicenseTerms(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsIds[0]
            )
        );

        // Verify custom fee was stored
        assertEq(bookContract.customLicenseFees(ipId), 10);

        // Verify royalty vault was deployed
        address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
        assertTrue(royaltyVault != address(0));
    }

    function test_RegisterBook_MultipleAuthors_SplitRoyalties() public {
        // Authorize bob as well
        vm.prank(owner);
        bookContract.setAuthorized(bob, true);

        // Setup co-author data
        address[] memory authors = new address[](2);
        authors[0] = alice;
        authors[1] = bob;
        uint256[] memory authorShares = new uint256[](2);
        authorShares[0] = 60_000_000; // Alice gets 60%
        authorShares[1] = 40_000_000; // Bob gets 40%

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Collaborative-Work"
        );
        uint8[] memory licenseTypes = new uint8[](2);
        licenseTypes[0] = 0; // Commercial Remix
        licenseTypes[1] = 1; // Non-Commercial Social Remixing

        // Empty royaltyShares for multi-author case
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = new WorkflowStructs.RoyaltyShare[](0);

        // Register collaborative book
        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice, // recipient (first author manages the IP)
                metadata,
                licenseTypes,
                5, // Commercial fee
                10_000_000, // 10% royalty
                royaltyShares, // Empty for multi-author
                authors, // Both authors
                authorShares, // Their respective shares
                false
            );

        // Verify registration success
        assertTrue(ipId != address(0));
        assertEq(licenseTermsIds.length, 2);

        // Both license types should be attached
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

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterBook_RevertWhen_UnauthorizedCaller() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Unauthorized-Book"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1; // Non-commercial
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(unauthorized);

        // Unauthorized user should not be able to register
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized to register books");
        bookContract.registerBook(
            unauthorized,
            metadata,
            licenseTypes,
            0,
            0,
            royaltyShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }

    function test_RegisterBook_RevertWhen_CollectionNotCreated() public {
        // Deploy a new contract without collection
        BookIPRegistrationAndManagement newContract = new BookIPRegistrationAndManagement(
                owner,
                address(REGISTRATION_WORKFLOWS),
                address(ROYALTY_DISTRIBUTION_WORKFLOWS),
                address(DERIVATIVE_WORKFLOWS),
                address(ROYALTY_WORKFLOWS),
                address(ROYALTY_MODULE),
                address(PIL_TEMPLATE),
                MERC20,
                ROYALTY_POLICY_LAP
            );

        // Authorize alice
        vm.prank(owner);
        newContract.setAuthorized(alice, true);

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "No-Collection-Book"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1;
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(alice);

        // Should fail without collection
        vm.prank(alice);
        vm.expectRevert("Collection not created");
        newContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            royaltyShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterBook_RevertWhen_InvalidLicenseTypes() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-License-Book"
        );
        uint8[] memory invalidLicenseTypes = new uint8[](1);
        invalidLicenseTypes[0] = 5; // Invalid type > 2
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(alice);

        vm.prank(alice);
        vm.expectRevert("Invalid license type");
        bookContract.registerBook(
            alice,
            metadata,
            invalidLicenseTypes,
            0,
            0,
            royaltyShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }

    function test_RegisterBook_RevertWhen_EmptyLicenseTypes() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "No-License-Book"
        );
        uint8[] memory emptyLicenseTypes = new uint8[](0);
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(alice);

        vm.prank(alice);
        vm.expectRevert("Invalid license types array");
        bookContract.registerBook(
            alice,
            metadata,
            emptyLicenseTypes,
            0,
            0,
            royaltyShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }

    function test_RegisterBook_RevertWhen_InvalidRoyaltyShares() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-Royalty-Book"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1; // Non-commercial

        // Create invalid royalty shares (doesn't sum to 100%)
        WorkflowStructs.RoyaltyShare[]
            memory invalidShares = new WorkflowStructs.RoyaltyShare[](1);
        invalidShares[0] = WorkflowStructs.RoyaltyShare({
            recipient: alice,
            percentage: 50_000_000 // Only 50%
        });

        vm.prank(alice);
        vm.expectRevert("Royalty shares must sum to 100%");
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            invalidShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterBook_EmitsCorrectEvents() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Event-Test-Book"
        );
        uint8[] memory licenseTypes = new uint8[](1);
        licenseTypes[0] = 1; // Non-commercial
        WorkflowStructs.RoyaltyShare[]
            memory royaltyShares = _createSingleAuthorRoyalty(alice);

        // Expect BookRegistered event
        vm.expectEmit(true, true, true, false);
        // We can't predict exact values, so we use false for data
        emit BookIPRegistrationAndManagement.BookRegistered(
            address(0), // ipId - will be calculated
            0, // tokenId - will be incremented
            new uint256[](1), // licenseTermsIds - will be generated
            address(0) // royaltyVault - will be deployed
        );

        vm.prank(alice);
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            royaltyShares,
            new address[](0),
            new uint256[](0),
            false
        );
    }
}
