// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../base/BaseTest.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {BookIPRegistrationAndManagement} from "../../src/BookIPRegistrationAndManagement.sol";

/// @title BookRegistration Test Suite
/// @notice Critical path tests for book IP registration functionality
/// @dev Tests single/multi-author flows, license attachment, and Story Protocol integration
/// @dev Run with: forge test --match-contract BookRegistrationTest -vvv
contract BookRegistrationTest is BaseTest {
    // SINGLE AUTHOR REGISTRATION - CRITICAL PATH

    /// @notice Test successful book registration with commercial license
    /// @dev Validates IP registration, NFT minting, license attachment, royalty vault, and IPAccount
    function test_RegisterBook_SingleAuthor_CommercialLicense() public {
        // Setup
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Alice-Adventures"
        );
        uint8[] memory licenseTypes = _toUint8Array(0); // Commercial Remix

        // Execute
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        ) = bookContract.registerBook(
                alice,
                metadata,
                licenseTypes,
                DEFAULT_COMMERCIAL_FEE,
                DEFAULT_COMMERCIAL_ROYALTY,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );
        uint256 gasUsed = gasBefore - gasleft();

        // Assertions - Basic Registration
        assertValidIPRegistration(ipId, alice, tokenId);
        assertEq(licenseTermsIds.length, 1, "Should have 1 license");

        // Assertions - License Parameters (Story Protocol Integration)
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertLicenseTermsParameters(
            licenseTermsIds[0],
            DEFAULT_COMMERCIAL_FEE,
            DEFAULT_COMMERCIAL_ROYALTY,
            true // commercialUse
        );

        // Assertions - IPAccount Deployment
        assertIPAccountDeployed(ipId, spgNftCollection, tokenId);

        // Gas Benchmark (soft warning)
        assertGasUsage(
            gasUsed,
            BOOK_REGISTRATION_GAS_THRESHOLD,
            "Single author commercial"
        );
    }

    /// @notice Test book registration with non-commercial license
    /// @dev Non-commercial licenses have zero minting fees and no revenue share
    function test_RegisterBook_SingleAuthor_NonCommercialLicense() public {
        // Setup
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "NonCommercial-Work"
        );
        uint8[] memory licenseTypes = _toUint8Array(1); // Non-Commercial Social Remixing

        // Execute
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

        // Assertions
        assertValidIPRegistration(ipId, alice, tokenId);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertLicenseTermsParameters(
            licenseTermsIds[0],
            0, // Zero fee
            0, // Zero royalty
            false // Non-commercial
        );
    }

    /// @notice Test book registration with multiple license types
    /// @dev Story Protocol allows attaching multiple license types to same IP
    function test_RegisterBook_SingleAuthor_MultipleLicenseTypes() public {
        // Setup
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Dual-License-Book"
        );
        uint8[] memory licenseTypes = _toUint8Array(0, 1); // Commercial + Non-Commercial

        // Execute
        vm.prank(alice);
        (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        ) = bookContract.registerBook(
                alice,
                metadata,
                licenseTypes,
                DEFAULT_COMMERCIAL_FEE,
                DEFAULT_COMMERCIAL_ROYALTY,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Assertions
        assertValidIPRegistration(ipId, alice, tokenId);
        assertEq(licenseTermsIds.length, 2, "Should have 2 licenses");

        // Verify both licenses attached with correct parameters
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[1]);

        // License 0: Commercial
        assertLicenseTermsParameters(
            licenseTermsIds[0],
            DEFAULT_COMMERCIAL_FEE,
            DEFAULT_COMMERCIAL_ROYALTY,
            true
        );

        // License 1: Non-Commercial
        assertLicenseTermsParameters(licenseTermsIds[1], 0, 0, false);
    }

    // MULTI-AUTHOR REGISTRATION - CRITICAL PATH

    /// @notice Test two-author registration with 60/40 royalty split
    /// @dev Validates royalty token distribution to multiple recipients
    function test_RegisterBook_TwoAuthors_SplitRoyalties() public {
        // Setup
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Collaborative-Novel"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        address[] memory authors = _toAddressArray(alice, bob);
        uint256[] memory authorShares = _toUint256Array(60_000_000, 40_000_000); // 60% / 40%

        // Execute
        vm.prank(alice);
        (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        ) = bookContract.registerBook(
                alice,
                metadata,
                licenseTypes,
                DEFAULT_COMMERCIAL_FEE,
                DEFAULT_COMMERCIAL_ROYALTY,
                new WorkflowStructs.RoyaltyShare[](0),
                authors,
                authorShares,
                false
            );

        // Assertions - Basic Registration
        assertValidIPRegistration(ipId, alice, tokenId);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);

        // Assertions - Royalty Distribution
        assertRoyaltyTokenDistribution(ipId, authors, authorShares);
    }

    /// @notice Test maximum collaborator registration (16 authors)
    /// @dev Story Protocol limits to 16 for gas optimization
    function test_RegisterBook_MaximumCollaborators() public {
        // Setup
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Max-Authors-Book"
        );
        uint8[] memory licenseTypes = _toUint8Array(1);

        address[] memory authors = new address[](MAX_COLLABORATORS);
        uint256[] memory authorShares = new uint256[](MAX_COLLABORATORS);

        // Equal distribution
        uint256 sharePerAuthor = PERCENTAGE_SCALE / MAX_COLLABORATORS;
        uint256 remainder = PERCENTAGE_SCALE % MAX_COLLABORATORS;

        for (uint256 i = 0; i < MAX_COLLABORATORS; i++) {
            authors[i] = makeAddr(string(abi.encodePacked("author", i)));
            authorShares[i] = sharePerAuthor;

            // Authorize and fund
            vm.prank(owner);
            bookContract.setAuthorized(authors[i], true);
            _fundAccount(authors[i], 1000 * 10 ** 18);
        }

        // Add remainder to last author
        authorShares[MAX_COLLABORATORS - 1] += remainder;
        _approveForAccount(authors[0], address(bookContract));

        // Execute
        vm.prank(authors[0]);
        (address ipId, uint256 tokenId, ) = bookContract.registerBook(
            authors[0],
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            authors,
            authorShares,
            false
        );

        // Assertions
        assertValidIPRegistration(ipId, authors[0], tokenId);
        assertRoyaltyTokenDistribution(ipId, authors, authorShares);
    }

    // VALIDATION & ERROR CASES - CRITICAL BUSINESS LOGIC

    /// @notice Test registration reverts when caller is unauthorized
    function test_RegisterBook_RevertWhen_Unauthorized() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Unauthorized-Book"
        );
        uint8[] memory licenseTypes = _toUint8Array(1);

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

    /// @notice Test registration reverts with invalid license type
    function test_RegisterBook_RevertWhen_InvalidLicenseType() public {
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-License"
        );
        uint8[] memory invalidLicenseTypes = _toUint8Array(5); // Invalid (max is 2)

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

    /// @notice Test registration reverts when royalty shares don't sum to 100%
    /// @dev Critical validation for multi-author royalty distribution
    function test_RegisterBook_RevertWhen_RoyaltySharesInvalid() public {
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-Shares"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        address[] memory authors = _toAddressArray(alice, bob);
        uint256[] memory invalidShares = _toUint256Array(
            60_000_000,
            30_000_000
        ); // Only 90%

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

    /// @notice Test registration reverts when authors and shares length mismatch
    function test_RegisterBook_RevertWhen_AuthorsSharesMismatch() public {
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Mismatch"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        address[] memory authors = _toAddressArray(alice, bob);
        uint256[] memory shares = _toUint256Array(100_000_000); // Only 1 share for 2 authors

        vm.prank(alice);
        vm.expectRevert(
            BookIPRegistrationAndManagement.InvalidAuthorData.selector
        );
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            authors,
            shares,
            false
        );
    }

    /// @notice Test registration reverts when exceeding collaborator limit
    function test_RegisterBook_RevertWhen_TooManyCollaborators() public {
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Too-Many"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        // Create 17 authors (exceeds MAX_COLLABORATORS = 16)
        address[] memory tooManyAuthors = new address[](17);
        uint256[] memory shares = new uint256[](17);

        for (uint256 i = 0; i < 17; i++) {
            tooManyAuthors[i] = makeAddr(string(abi.encodePacked("author", i)));
            shares[i] = PERCENTAGE_SCALE / 17;
        }
        shares[16] += PERCENTAGE_SCALE % 17;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BookIPRegistrationAndManagement.TooManyCollaborators.selector,
                17,
                MAX_COLLABORATORS
            )
        );
        bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            tooManyAuthors,
            shares,
            false
        );
    }

    /// @notice Test registration reverts when contract is paused
    function test_RegisterBook_RevertWhen_ContractPaused() public {
        // Setup
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        // Pause contract
        vm.prank(owner);
        bookContract.pause();

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Paused"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        // Expect revert with Pausable error
        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
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
    }

    /// @notice Test registration reverts when collection not created
    function test_RegisterBook_RevertWhen_CollectionNotCreated() public {
        // Deploy fresh contract without creating collection
        BookIPRegistrationAndManagement freshContract = new BookIPRegistrationAndManagement(
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
        freshContract.setAuthorized(alice, true);

        _fundAccount(alice, 1000 * 10 ** 18);
        vm.prank(alice);
        MERC20.approve(address(freshContract), type(uint256).max);

        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "No-Collection"
        );
        uint8[] memory licenseTypes = _toUint8Array(0);

        vm.prank(alice);
        vm.expectRevert(
            BookIPRegistrationAndManagement.CollectionNotCreated.selector
        );
        freshContract.registerBook(
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
    }
}
