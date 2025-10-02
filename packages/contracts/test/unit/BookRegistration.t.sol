// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../base/BaseTest.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {BookIPRegistrationAndManagement} from "../../src/BookIPRegistrationAndManagement.sol";

/// @title BookRegistration Test Suite
/// @notice Comprehensive tests for book IP registration functionality
/// @dev Tests cover single/multi-author registration, license attachment, and validation
/// @dev Run with: forge test --match-contract BookRegistrationTest -vvv
contract BookRegistrationTest is BaseTest {
    // Single Author Registration Tests

    /// @notice Test successful book registration with commercial license
    /// @dev Validates IP registration, NFT minting, license attachment, and royalty vault deployment
    function test_RegisterBook_SingleAuthor_CommercialLicense() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Alice-Adventures"
        );
        uint8[] memory licenseTypes = _toUint8Array(0); // Commercial Remix

        uint256 gasBefore = _measureGas();

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

        uint256 gasUsed = _calculateGasUsed(gasBefore);

        // Assertions using custom helpers
        assertValidIPRegistration(ipId, alice, tokenId);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertEq(licenseTermsIds.length, 1, "Should have 1 license");
        assertGasUsage(
            gasUsed,
            BOOK_REGISTRATION_GAS_THRESHOLD,
            "Single author registration"
        );
    }

    /// @notice Test book registration with non-commercial license
    /// @dev Non-commercial licenses have zero minting fees
    function test_RegisterBook_SingleAuthor_NonCommercialLicense() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "NonCommercial-Work"
        );
        uint8[] memory licenseTypes = _toUint8Array(1); // Non-Commercial Social Remixing

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

        assertValidIPRegistration(ipId, alice, tokenId);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
    }

    /// @notice Test book registration with Creative Commons license
    function test_RegisterBook_SingleAuthor_CreativeCommonsLicense() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "CC-BY-Work"
        );
        uint8[] memory licenseTypes = _toUint8Array(2); // Creative Commons Attribution

        vm.prank(alice);
        (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        ) = bookContract.registerBook(
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

        assertValidIPRegistration(ipId, alice, tokenId);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
    }

    /// @notice Test book registration with multiple license types (Commercial + Non-Commercial)
    /// @dev Story Protocol allows attaching multiple license types to same IP
    function test_RegisterBook_SingleAuthor_MultipleLicenseTypes() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Dual-License-Book"
        );
        uint8[] memory licenseTypes = _toUint8Array(0, 1); // Commercial + Non-Commercial

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

        assertValidIPRegistration(ipId, alice, tokenId);
        assertEq(licenseTermsIds.length, 2, "Should have 2 licenses");

        // Verify both licenses are attached
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[1]);
    }

    // Multi-Author Registration Tests

    /// @notice Test two-author registration with 60/40 royalty split
    /// @dev Validates correct royalty share distribution
    function test_RegisterBook_TwoAuthors_SplitRoyalties() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Collaborative-Novel"
        );
        uint8[] memory licenseTypes = _toUint8Array(0, 1);

        address[] memory authors = _toAddressArray(alice, bob);
        uint256[] memory authorShares = _toUint256Array(60_000_000, 40_000_000); // 60% / 40%

        vm.prank(alice);
        (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) = bookContract
            .registerBook(
                alice, // Recipient (manages NFT)
                metadata,
                licenseTypes,
                DEFAULT_COMMERCIAL_FEE,
                DEFAULT_COMMERCIAL_ROYALTY,
                new WorkflowStructs.RoyaltyShare[](0),
                authors,
                authorShares,
                false
            );

        assertValidIPRegistration(ipId, alice, tokenId);
        assertEq(licenseTermsIds.length, 2, "Should have 2 license types");

        // Verify both licenses attached
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[0]);
        assertLicenseAttached(ipId, address(PIL_TEMPLATE), licenseTermsIds[1]);
    }

    /// @notice Test three-author registration with equal shares
    function test_RegisterBook_ThreeAuthors_EqualShares() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Trio-Novel"
        );
        uint8[] memory licenseTypes = _toUint8Array(1);

        address[] memory authors = new address[](3);
        authors[0] = alice;
        authors[1] = bob;
        authors[2] = carol;

        uint256[] memory authorShares = new uint256[](3);
        authorShares[0] = 33_333_333; // ~33.33%
        authorShares[1] = 33_333_333; // ~33.33%
        authorShares[2] = 33_333_334; // ~33.34% (accounts for rounding)

        vm.prank(alice);
        (address ipId, uint256 tokenId, ) = bookContract.registerBook(
            alice,
            metadata,
            licenseTypes,
            0,
            0,
            new WorkflowStructs.RoyaltyShare[](0),
            authors,
            authorShares,
            false
        );

        assertValidIPRegistration(ipId, alice, tokenId);
    }

    /// @notice Test maximum collaborator registration (16 authors)
    /// @dev Story Protocol limits parent IPs to 16 for gas optimization
    function test_RegisterBook_MaximumCollaborators() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Max-Authors-Book"
        );
        uint8[] memory licenseTypes = _toUint8Array(1);

        address[] memory authors = new address[](MAX_COLLABORATORS);
        uint256[] memory authorShares = new uint256[](MAX_COLLABORATORS);

        // Equal distribution across 16 authors
        uint256 sharePerAuthor = PERCENTAGE_SCALE / MAX_COLLABORATORS;
        uint256 remainder = PERCENTAGE_SCALE % MAX_COLLABORATORS;

        for (uint256 i = 0; i < MAX_COLLABORATORS; i++) {
            authors[i] = makeAddr(string(abi.encodePacked("author", i)));
            authorShares[i] = sharePerAuthor;

            // Authorize each author
            vm.prank(owner);
            bookContract.setAuthorized(authors[i], true);
        }

        // Add remainder to last author to ensure sum equals PERCENTAGE_SCALE
        authorShares[MAX_COLLABORATORS - 1] += remainder;

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

        assertValidIPRegistration(ipId, authors[0], tokenId);
    }

    // Validation & Error Tests

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

    /// @notice Test registration reverts with invalid license type (> 2)
    function test_RegisterBook_RevertWhen_InvalidLicenseType() public {
        WorkflowStructs.IPMetadata memory metadata = _createBookMetadata(
            "Invalid-License"
        );
        uint8[] memory invalidLicenseTypes = _toUint8Array(5); // Invalid

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
}
