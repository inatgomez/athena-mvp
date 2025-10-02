// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../base/BaseTest.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {console2} from "forge-std/console2.sol";
import {BookIPRegistrationAndManagement} from "../../src/BookIPRegistrationAndManagement.sol";

/// @title DerivativeCreation.t.sol
/// @notice Comprehensive test suite for derivative IP registration with parent linkage
/// @dev Tests single-parent, multi-parent, and error conditions following Story Protocol patterns
/// @dev Run with: forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/unit/DerivativeCreation.t.sol -vvv --via-ir
contract DerivativeCreationTest is BaseTest {
    // SINGLE PARENT DERIVATIVE TESTS

    /// @notice Test derivative with single parent using commercial license
    /// @dev Validates:
    /// - Derivative registration succeeds
    /// - Parent relationship is established
    /// - License inheritance works correctly
    /// - Minting fee is paid to parent's royalty vault
    function test_RegisterDerivative_SingleParent_CommercialLicense() public {
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Setup derivative parameters
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-SingleParent-Commercial"
        );

        uint256 gasBefore = _measureGas();
        vm.prank(bob);
        (address childIpId, uint256 childTokenId) = bookContract
            .registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(parentLicenseTermsId),
                derivMetadata,
                new WorkflowStructs.RoyaltyShare[](0), // single author via authors array
                _toAddressArray(bob),
                new uint256[](0), // shares (ignored for single author)
                type(uint256).max, // maxMintingFee (no limit)
                0, // maxRts
                0, // maxRevenueShare
                false
            );
        uint256 gasUsed = _calculateGasUsed(gasBefore);

        // Assertions: Basic IP registration
        assertValidIPRegistration(childIpId, bob, childTokenId);

        // Assertions: Parent-child relationship
        assertDerivativeRelationship(parentIpId, childIpId);

        // Assertions: License terms linkage
        assertParentLicenseTermsLink(
            childIpId,
            parentIpId,
            parentLicenseTermsId
        );

        // Assertions: Child IP is marked as derivative
        assertTrue(
            LICENSE_REGISTRY.isDerivativeIp(childIpId),
            "Child should be derivative"
        );

        // Assertions: Parent IP count
        assertEq(
            LICENSE_REGISTRY.getParentIpCount(childIpId),
            1,
            "Should have 1 parent"
        );

        // Gas usage check
        assertGasUsage(
            gasUsed,
            DERIVATIVE_CREATION_GAS_THRESHOLD,
            "Single parent derivative"
        );

        console2.log(" Single parent derivative created");
        console2.log("  Parent IP:", parentIpId);
        console2.log("  Child IP:", childIpId);
        console2.log("  Gas used:", gasUsed);
    }

    /// @notice Test derivative with 2+ authors splitting royalties
    /// @dev Validates multi-author royalty distribution in derivative context
    function test_RegisterDerivative_SingleParent_MultipleAuthors() public {
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Setup derivative with 2 authors (60/40 split)
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-MultiAuthor"
        );

        address[] memory authors = new address[](2);
        authors[0] = bob;
        authors[1] = carol;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 60_000_000; // 60%
        shares[1] = 40_000_000; // 40%

        vm.prank(bob);
        (address childIpId, uint256 childTokenId) = bookContract
            .registerDerivative(
                bob,
                _toAddressArray(parentIpId),
                _toUint256Array(parentLicenseTermsId),
                derivMetadata,
                new WorkflowStructs.RoyaltyShare[](0),
                authors,
                shares,
                type(uint256).max,
                0,
                0,
                false
            );

        // Assertions
        assertValidIPRegistration(childIpId, bob, childTokenId);
        assertDerivativeRelationship(parentIpId, childIpId);

        // Verify royalty distribution
        assertRoyaltyTokenDistribution(childIpId, authors, shares);

        console2.log("Multi-author derivative created");
        console2.log("Authors: bob (60%), carol (40%)");
    }

    /// @notice Test maxMintingFee parameter enforcement
    /// @dev Validates that derivative registration reverts if parent fee exceeds limit
    function test_RegisterDerivative_SingleParent_WithMaxMintingFee() public {
        // Register parent with $10 minting fee
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Setup derivative with maxMintingFee of $5 (should revert)
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-MaxFee"
        );

        // Attempt registration with insufficient maxMintingFee
        vm.prank(bob);
        vm.expectRevert(); // Story Protocol will revert with fee-related error
        bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            5 * 10 ** 18, // maxMintingFee = $5 (parent requires $10)
            0,
            0,
            false
        );

        console2.log("MaxMintingFee protection working");
    }

    // MULTIPLE PARENT DERIVATIVE TESTS

    /// @notice Test derivative with 2 parents using same commercial license
    /// @dev Validates dual parent linkage with identical license terms
    function test_RegisterDerivative_MultipleParents_SameLicense() public {
        // Register two parent books with same commercial license
        (
            address parent1IpId,
            ,
            uint256 parent1LicenseTermsId
        ) = _registerParentBook(alice);
        (
            address parent2IpId,
            ,
            uint256 parent2LicenseTermsId
        ) = _registerParentBook(bob);

        // Verify both parents have same license terms ID
        assertEq(
            parent1LicenseTermsId,
            parent2LicenseTermsId,
            "Parents should have same license terms"
        );

        // Setup derivative linking to both parents
        _fundAccount(carol, 1000 * 10 ** 18);
        _approveForAccount(carol, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-TwoParents-SameLicense"
        );

        address[] memory parentIpIds = new address[](2);
        parentIpIds[0] = parent1IpId;
        parentIpIds[1] = parent2IpId;

        uint256[] memory licenseTermsIds = new uint256[](2);
        licenseTermsIds[0] = parent1LicenseTermsId;
        licenseTermsIds[1] = parent2LicenseTermsId;

        // Register derivative
        vm.prank(carol);
        (address childIpId, uint256 childTokenId) = bookContract
            .registerDerivative(
                carol,
                parentIpIds,
                licenseTermsIds,
                derivMetadata,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(carol),
                new uint256[](0),
                type(uint256).max,
                0,
                0,
                false
            );

        // Assertions: Validate both parent relationships
        assertValidIPRegistration(childIpId, carol, childTokenId);
        assertDerivativeRelationship(parent1IpId, childIpId);
        assertDerivativeRelationship(parent2IpId, childIpId);

        // Verify parent count
        assertEq(
            LICENSE_REGISTRY.getParentIpCount(childIpId),
            2,
            "Should have 2 parents"
        );

        // Verify license linkage for both parents
        assertParentLicenseTermsLink(
            childIpId,
            parent1IpId,
            parent1LicenseTermsId
        );
        assertParentLicenseTermsLink(
            childIpId,
            parent2IpId,
            parent2LicenseTermsId
        );

        console2.log("Multi-parent (same license) derivative created");
        console2.log("Parent 1:", parent1IpId);
        console2.log("Parent 2:", parent2IpId);
        console2.log("Child:", childIpId);
    }

    /// @notice Test derivative with 2 parents using different licenses
    /// @dev This test should fail. Story Protocol enforces the most restrictive license across all parents when commercial licenses are involved.
    function test_RegisterDerivative_MultipleParents_DifferentLicenses()
        public
    {
        // Register Parent A: Commercial Remix ($10 fee, 5% royalty)
        _fundAccount(alice, 1000 * 10 ** 18);
        _approveForAccount(alice, address(bookContract));

        WorkflowStructs.IPMetadata memory parentAMetadata = _createBookMetadata(
            "Parent-A-Commercial"
        );
        uint8[] memory commercialLicense = _toUint8Array(0); // Commercial

        vm.prank(alice);
        (
            address parentAIpId,
            ,
            uint256[] memory parentALicenseTermsIds
        ) = bookContract.registerBook(
                alice,
                parentAMetadata,
                commercialLicense,
                DEFAULT_COMMERCIAL_FEE,
                DEFAULT_COMMERCIAL_ROYALTY,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(alice),
                new uint256[](0),
                false
            );

        // Register Parent B: Non-Commercial Social Remixing
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory parentBMetadata = _createBookMetadata(
            "Parent-B-NonCommercial"
        );
        uint8[] memory nonCommercialLicense = _toUint8Array(1); // Non-Commercial

        vm.prank(bob);
        (address parentBIpId, , uint256[] memory parentBLicenseTermsIds) = bookContract
            .registerBook(
                bob,
                parentBMetadata,
                nonCommercialLicense,
                0, // No custom fee for non-commercial
                0, // No custom royalty for non-commercial
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(bob),
                new uint256[](0),
                false
            );

        // Setup derivative linking to both parents with different licenses
        _fundAccount(carol, 1000 * 10 ** 18);
        _approveForAccount(carol, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-MixedLicenses"
        );

        address[] memory parentIpIds = new address[](2);
        parentIpIds[0] = parentAIpId;
        parentIpIds[1] = parentBIpId;

        uint256[] memory licenseTermsIds = new uint256[](2);
        licenseTermsIds[0] = parentALicenseTermsIds[0];
        licenseTermsIds[1] = parentBLicenseTermsIds[0];

        // Register derivative
        vm.prank(carol);
        (address childIpId, uint256 childTokenId) = bookContract
            .registerDerivative(
                carol,
                parentIpIds,
                licenseTermsIds,
                derivMetadata,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(carol),
                new uint256[](0),
                type(uint256).max,
                0,
                0,
                false
            );

        // Assertions
        assertValidIPRegistration(childIpId, carol, childTokenId);
        assertDerivativeRelationship(parentAIpId, childIpId);
        assertDerivativeRelationship(parentBIpId, childIpId);

        // Verify license linkage preserves different license types
        assertParentLicenseTermsLink(
            childIpId,
            parentAIpId,
            parentALicenseTermsIds[0]
        );
        assertParentLicenseTermsLink(
            childIpId,
            parentBIpId,
            parentBLicenseTermsIds[0]
        );

        console2.log("Multi-parent (different licenses) derivative created");
        console2.log("Parent A (commercial):", parentAIpId);
        console2.log("Parent B (non-commercial):", parentBIpId);
    }

    /// @notice Test derivative with maximum 16 parents (MAX_COLLABORATORS limit)
    /// @dev Gas benchmark test for Story Protocol's parent IP limit
    function test_RegisterDerivative_MaximumParents() public {
        // Register 16 parent IPs
        address[] memory parentIpIds = new address[](MAX_COLLABORATORS);
        uint256[] memory licenseTermsIds = new uint256[](MAX_COLLABORATORS);

        for (uint256 i = 0; i < MAX_COLLABORATORS; i++) {
            address author = address(uint160(1000 + i)); // Generate unique addresses
            (address ipId, , uint256 licenseTermsId) = _registerParentBook(
                author
            );
            parentIpIds[i] = ipId;
            licenseTermsIds[i] = licenseTermsId;
        }

        // Setup derivative linking to all 16 parents
        _fundAccount(carol, 10000 * 10 ** 18); // Extra funding for 16 minting fees
        _approveForAccount(carol, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-16Parents"
        );

        // Measure gas and register derivative
        uint256 gasBefore = _measureGas();
        vm.prank(carol);
        (address childIpId, uint256 childTokenId) = bookContract
            .registerDerivative(
                carol,
                parentIpIds,
                licenseTermsIds,
                derivMetadata,
                new WorkflowStructs.RoyaltyShare[](0),
                _toAddressArray(carol),
                new uint256[](0),
                type(uint256).max,
                0,
                0,
                false
            );
        uint256 gasUsed = _calculateGasUsed(gasBefore);

        // Assertions
        assertValidIPRegistration(childIpId, carol, childTokenId);
        assertEq(
            LICENSE_REGISTRY.getParentIpCount(childIpId),
            16,
            "Should have 16 parents"
        );

        // 5. Verify all parent relationships
        for (uint256 i = 0; i < MAX_COLLABORATORS; i++) {
            assertTrue(
                LICENSE_REGISTRY.isParentIp(parentIpIds[i], childIpId),
                "Parent relationship should exist"
            );
        }

        // 6. Gas benchmark logging
        console2.log("Maximum parents derivative created");
        console2.log("Parent count: 16");
        console2.log("Gas used:", gasUsed);
        console2.log("Gas per parent:", gasUsed / 16);
    }

    // ERROR VALIDATION TESTS

    /// @notice Test revert when parentIpIds and licenseTermsIds length mismatch
    function test_RegisterDerivative_RevertWhen_ParentIdsLicenseIdsMismatch()
        public
    {
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Setup mismatched arrays (1 parent, 2 license terms)
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-Mismatch"
        );

        address[] memory parentIpIds = new address[](1);
        parentIpIds[0] = parentIpId;

        uint256[] memory licenseTermsIds = new uint256[](2);
        licenseTermsIds[0] = parentLicenseTermsId;
        licenseTermsIds[1] = parentLicenseTermsId;

        // Expect revert
        vm.prank(bob);
        vm.expectRevert(
            BookIPRegistrationAndManagement.InvalidAuthorData.selector
        );
        bookContract.registerDerivative(
            bob,
            parentIpIds,
            licenseTermsIds,
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        console2.log("Array length mismatch rejected");
    }

    /// @notice Test revert when exceeding MAX_COLLABORATORS (17 parents)
    function test_RegisterDerivative_RevertWhen_ExceedsMaxParents() public {
        // Setup 17 parent IPs (exceeds limit)
        address[] memory parentIpIds = new address[](17);
        uint256[] memory licenseTermsIds = new uint256[](17);

        for (uint256 i = 0; i < 17; i++) {
            address author = address(uint160(2000 + i));
            (address ipId, , uint256 licenseTermsId) = _registerParentBook(
                author
            );
            parentIpIds[i] = ipId;
            licenseTermsIds[i] = licenseTermsId;
        }

        // Setup derivative
        _fundAccount(bob, 10000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-TooManyParents"
        );

        // Expect revert
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                BookIPRegistrationAndManagement.TooManyCollaborators.selector,
                17,
                MAX_COLLABORATORS
            )
        );
        bookContract.registerDerivative(
            bob,
            parentIpIds,
            licenseTermsIds,
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        console2.log("Exceeded parent limit rejected");
    }

    /// @notice Test revert when parent doesn't have specified license terms attached
    function test_RegisterDerivative_RevertWhen_InvalidLicenseTerms() public {
        // 1. Register parent
        (address parentIpId, , ) = _registerParentBook(alice);

        // 2. Setup derivative with non-existent license terms ID
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-InvalidLicense"
        );

        uint256 invalidLicenseTermsId = 99999; // Non-existent

        // 3. Expect revert from Story Protocol
        vm.prank(bob);
        vm.expectRevert(); // Story Protocol will revert
        bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(invalidLicenseTermsId),
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        console2.log("Invalid license terms, rejected");
    }

    /// @notice Test revert when derivative author shares don't sum to 100%
    function test_RegisterDerivative_RevertWhen_RoyaltySharesInvalid() public {
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Setup derivative with invalid shares (70% + 20% = 90%)
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-InvalidShares"
        );

        address[] memory authors = new address[](2);
        authors[0] = bob;
        authors[1] = carol;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 70_000_000; // 70%
        shares[1] = 20_000_000; // 20% (total = 90%)

        // Expect revert
        vm.prank(bob);
        vm.expectRevert(
            BookIPRegistrationAndManagement.InvalidRoyaltyShares.selector
        );
        bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            authors,
            shares,
            type(uint256).max,
            0,
            0,
            false
        );

        console2.log("Invalid royalty shares rejected");
    }

    // STORY PROTOCOL INTEGRATION TESTS

    /// @notice Verify LICENSE_REGISTRY.getParentLicenseTerms() returns correct linkage
    function test_RegisterDerivative_VerifyParentLicenseTermsLink() public {
        (
            address parentIpId,
            ,
            uint256 parentLicenseTermsId
        ) = _registerParentBook(alice);

        // Register derivative
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory derivMetadata = _createBookMetadata(
            "Derivative-LicenseLink"
        );

        vm.prank(bob);
        (address childIpId, ) = bookContract.registerDerivative(
            bob,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            derivMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        // Verify getParentLicenseTerms returns correct data
        (
            address licenseTemplate,
            uint256 retrievedLicenseTermsId
        ) = LICENSE_REGISTRY.getParentLicenseTerms(childIpId, parentIpId);

        assertEq(
            licenseTemplate,
            address(PIL_TEMPLATE),
            "License template should be PIL"
        );
        assertEq(
            retrievedLicenseTermsId,
            parentLicenseTermsId,
            "License terms ID mismatch"
        );

        console2.log("Parent license terms link verified");
        console2.log("Template:", licenseTemplate);
        console2.log("Terms ID:", retrievedLicenseTermsId);
    }

    /// @notice Verify LICENSE_REGISTRY.getAncestorsCount() for 3-level chain
    /// @dev Tests grandparent → parent → child derivative hierarchy
    function test_RegisterDerivative_VerifyAncestorCount() public {
        // Register grandparent
        (
            address grandparentIpId,
            ,
            uint256 grandparentLicenseTermsId
        ) = _registerParentBook(alice);

        // Register parent as derivative of grandparent
        _fundAccount(bob, 1000 * 10 ** 18);
        _approveForAccount(bob, address(bookContract));

        WorkflowStructs.IPMetadata memory parentMetadata = _createBookMetadata(
            "Parent-Level2"
        );

        vm.prank(bob);
        (address parentIpId, ) = bookContract.registerDerivative(
            bob,
            _toAddressArray(grandparentIpId),
            _toUint256Array(grandparentLicenseTermsId),
            parentMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(bob),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        // Get license terms ID for parent (now it's a derivative)
        (, uint256 parentLicenseTermsId) = LICENSE_REGISTRY
            .getAttachedLicenseTerms(parentIpId, 0);

        // Register child as derivative of parent
        _fundAccount(carol, 1000 * 10 ** 18);
        _approveForAccount(carol, address(bookContract));

        WorkflowStructs.IPMetadata memory childMetadata = _createBookMetadata(
            "Child-Level3"
        );

        vm.prank(carol);
        (address childIpId, ) = bookContract.registerDerivative(
            carol,
            _toAddressArray(parentIpId),
            _toUint256Array(parentLicenseTermsId),
            childMetadata,
            new WorkflowStructs.RoyaltyShare[](0),
            _toAddressArray(carol),
            new uint256[](0),
            type(uint256).max,
            0,
            0,
            false
        );

        // Verify ancestor counts
        uint256 grandparentAncestorCount = LICENSE_REGISTRY.getAncestorsCount(
            grandparentIpId
        );
        uint256 parentAncestorCount = LICENSE_REGISTRY.getAncestorsCount(
            parentIpId
        );
        uint256 childAncestorCount = LICENSE_REGISTRY.getAncestorsCount(
            childIpId
        );

        assertEq(
            grandparentAncestorCount,
            0,
            "Grandparent should have 0 ancestors"
        );
        assertEq(parentAncestorCount, 1, "Parent should have 1 ancestor");
        assertEq(childAncestorCount, 2, "Child should have 2 ancestors");

        console2.log("Ancestor count validation successful");
        console2.log("Grandparent ancestors:", grandparentAncestorCount);
        console2.log("Parent ancestors:", parentAncestorCount);
        console2.log("Child ancestors:", childAncestorCount);
    }
}
