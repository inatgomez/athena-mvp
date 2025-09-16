//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {IRoyaltyTokenDistributionWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {IRoyaltyWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {Licensing} from "@storyprotocol/core/lib/Licensing.sol";
import {PILFlavors} from "@storyprotocol/core/lib/PILFlavors.sol";

///@title BookIPRegistrationAndManagement.sol
///@notice Gateway contract for registering books as IP on Story Protocol with full royalty management.

contract BookIPRegistrationAndManagement is Ownable, Pausable {
    // State variables
    IRegistrationWorkflows public immutable registrationWorkflows;
    IRoyaltyTokenDistributionWorkflows
        public immutable royaltyDistributionWorkflows;
    IDerivativeWorkflows public immutable derivativeWorkflows;
    IRoyaltyWorkflows public immutable royaltyWorkflows;
    address public spgNftCollection;

    // PIL Template and supported currency
    address public immutable pilTemplate;
    address public immutable supportedCurrency; // Wrapped $IP
    address public immutable royaltyPolicyAddress; //LAP Policy

    // Whitelisting for authors (root IPs only)
    mapping(address => bool) public authorizedAuthors;

    // Custom license fees (ipId => fee in wei)
    mapping(address => uint256) public customLicenseFees;

    // Events
    event BookCollectionCreated(address indexed collection);
    event BookRegistered(
        address indexed ipId,
        uint256 indexed tokenId,
        uint256[] indexed licenseTerms,
        address royaltyVault
    );
    event DerivativeCreated(
        address indexed childIpId,
        uint256 indexed tokenId,
        address indexed parentIpId,
        uint256 licensingFeesPaid
    );
    event RoyaltiesClaimed(
        address indexed ipId,
        address indexed claimer,
        uint256[] amounts
    );

    constructor(
        address initialOwner,
        address _registrationWorkflows,
        address _royaltyDistributionWorkflows,
        address _derivativeWorkflows,
        address _royaltyWorkflows,
        address _pilTemplate,
        address _supportedCurrency,
        address _royaltyPolicyAddress
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero address");
        require(
            _registrationWorkflows != address(0),
            "Invalid RegistrationWorkflows address"
        );
        require(
            _royaltyDistributionWorkflows != address(0),
            "Invalid RoyaltyDistributionWorkflows address"
        );
        require(
            _derivativeWorkflows != address(0),
            "Invalid DerivativeWorkflows address"
        );
        require(
            _royaltyWorkflows != address(0),
            "Invalid RoyaltyWorkflows address"
        );
        require(_pilTemplate != address(0), "Invalid PIL template address");
        require(_supportedCurrency != address(0), "Invalid currency address");
        require(
            _royaltyPolicyAddress != address(0),
            "Invalid royalty policy address"
        );

        registrationWorkflows = IRegistrationWorkflows(_registrationWorkflows);
        royaltyDistributionWorkflows = IRoyaltyTokenDistributionWorkflows(
            _royaltyDistributionWorkflows
        );
        derivativeWorkflows = IDerivativeWorkflows(_derivativeWorkflows);
        royaltyWorkflows = IRoyaltyWorkflows(_royaltyWorkflows);
        pilTemplate = _pilTemplate;
        supportedCurrency = _supportedCurrency;
        royaltyPolicyAddress = _royaltyPolicyAddress;
    }

    ///@notice Creates the SPGNFT collection for books
    ///@param spgNftInitParams Initialization parameters for the collection
    function createBookCollection(
        ISPGNFT.InitParams calldata spgNftInitParams
    ) external onlyOwner whenNotPaused {
        require(spgNftCollection == address(0), "Collection already created");
        require(bytes(spgNftInitParams.name).length > 0, "Name required");
        require(spgNftInitParams.maxSupply > 0, "Invalid max supply");
        require(
            spgNftInitParams.owner == address(this),
            "Owner must be this contract"
        );

        spgNftCollection = registrationWorkflows.createCollection(
            spgNftInitParams
        );
        emit BookCollectionCreated(spgNftCollection);
    }

    ///@notice Whitelist an author for book registration
    ///@param author The author's address
    ///@param authorized True to whitelist, false to remove
    function setAuthorized(address author, bool authorized) external onlyOwner {
        authorizedAuthors[author] = authorized;
    }

    ///@notice Register a book as original IP with integrated royalty management
    ///@dev Uses royalty distribution workflows for atomic IP+license+royalty setup
    ///@param recipient The recipient of the IP Asset (the author)
    ///@param ipMetadata Metadata for the IP Asset (the book)
    ///@param licenseTypes Array of license types to attach (0: Commercial Remix, 1: Non-Commercial Remix, 2: Creative Commons)
    ///@param customCommercialFee Custom fee for commercial license (only used if licenseType == 1)
    ///@param customRoyaltyShare Custom royalty share percentage (only used if licenseType == 1)
    ///@param royaltyShares Information for royalty token distribution
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return ipId The IP Asset ID
    ///@return tokenId the NFT token ID
    ///@return licenseTermsIds The IDs of the license terms attached to the IP Asset
    function registerBookWithSponsoredGas(
        address recipient,
        WorkflowStructs.IPMetadata calldata ipMetadata,
        uint8[] calldata licenseTypes,
        uint256 customCommercialFee,
        uint32 customRoyaltyShare,
        WorkflowStructs.RoyaltyShare[] calldata royaltyShares,
        bool allowDuplicates
    )
        external
        returns (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        )
    {
        require(spgNftCollection != address(0), "Collection not created");
        require(
            authorizedAuthors[msg.sender] || msg.sender == owner(),
            "Not authorized to register books"
        );
        require(
            licenseTypes.length > 0 && licenseTypes.length <= 3,
            "Invalid license types array"
        );

        // TODO: Implement gas sponsoring logic here
        // This could be done through meta-transactions or by the contract paying

        // Validate royalty shares sum to 100%
        uint32 totalShares = 0;
        for (uint i = 0; i < royaltyShares.length; i++) {
            totalShares += royaltyShares[i].percentage;
        }
        require(totalShares == 100_000_000, "Royalty shares must sum to 100%");

        // Validate all license types
        for (uint i = 0; i < licenseTypes.length; i++) {
            require(licenseTypes[i] <= 2, "Invalid license type");
        }

        // Get license terms for all requested types
        WorkflowStructs.LicenseTermsData[]
            memory licenseTermsData = _getMultipleLicenseTerms(
                licenseTypes,
                customCommercialFee,
                customRoyaltyShare
            );

        // Mint + Register + Attach Licenses + Deploy Vault + Distribute Royalty Tokens
        (ipId, tokenId, licenseTermsIds) = royaltyDistributionWorkflows
            .mintAndRegisterIpAndAttachPILTermsAndDistributeRoyaltyTokens(
                spgNftCollection,
                recipient,
                ipMetadata,
                licenseTermsData,
                royaltyShares,
                allowDuplicates
            );

        // Store custom fee if commercial license is included
        if (_hasCommercialLicense(licenseTypes) && customCommercialFee > 0) {
            customLicenseFees[ipId] = customCommercialFee;
        }

        // Get the deployed royalty vault address for the event
        // Note: RoyaltyModule.ipRoyaltyVaults(ipId) would return the vault address

        emit BookRegistered(ipId, tokenId, licenseTermsIds, address(0)); // TODO: get actual vault address
    }

    ///@notice Register a derivative work
    ///@dev Users pay licensing fees directly to parent IP owners via LAP policy
    ///@param derivativeRecipient Recipient of the derivative IP Asset
    ///@param parentIpIds Array of parent IP Asset IDs this derivative is based on (Max 16 parents)
    ///@param licenseTermsIds Array of license terms IDs corresponding to each parent
    ///@param derivativeMetadata Metadata for the derivative IP Asset
    ///@param maxMintingFee Maximum fee the user is willing to pay
    ///@param maxRts Maximum royalty tokens for external policies
    ///@param maxRevenueShare Maximum revenue share percentage
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return childIpId The ID of the newly created derivative IP Asset
    ///@return tokenId The NFT token ID of the derivative
    function registerDerivative(
        address derivativeRecipient,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds,
        WorkflowStructs.IPMetadata calldata derivativeMetadata,
        uint256 maxMintingFee,
        uint32 maxRts,
        uint32 maxRevenueShare,
        bool allowDuplicates
    ) external returns (address childIpId, uint256 tokenId) {
        require(spgNftCollection != address(0), "Collection not created");
        require(
            parentIpIds.length == licenseTermsIds.length,
            "Arrays length mismatch"
        );
        require(parentIpIds.length > 0, "Must have at least one parent");

        // Create the derivative data structure
        WorkflowStructs.MakeDerivative memory derivativeData = WorkflowStructs
            .MakeDerivative({
                parentIpIds: parentIpIds,
                licenseTermsIds: licenseTermsIds,
                licenseTemplate: pilTemplate,
                royaltyContext: "",
                maxMintingFee: maxMintingFee,
                maxRts: maxRts,
                maxRevenueShare: maxRevenueShare
            });

        // User must have approved this contract to spend their tokens for fees
        // Fees are automatically collected by the DerivativeWorkflows contract
        (childIpId, tokenId) = derivativeWorkflows
            .mintAndRegisterIpAndMakeDerivative(
                spgNftCollection,
                derivativeData,
                derivativeMetadata,
                derivativeRecipient,
                allowDuplicates
            );

        require(childIpId != address(0), "Derivative creation failed");

        // Calculate total licensing fees paid (approximate)
        uint256 totalFeesPaid = maxMintingFee; // This is user's max willingness to pay in case of parent IP changing fees during tx

        emit DerivativeCreated(
            childIpId,
            tokenId,
            parentIpIds[0],
            totalFeesPaid
        );
    }

    ///@notice Register derivative with integrated royalty distribution
    ///@dev Alternative approach for derivatives that need custom royalty token distribution
    ///@param derivativeRecipient Recipient of the derivative IP Asset
    ///@param derivativeMetadata Metadata for the derivative IP Asset
    ///@param derivativeData Data structure defining the derivative creation parameters
    ///@param royaltyShares Information for royalty token distribution
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return childIpId The ID of the newly created derivative IP Asset
    ///@return tokenId The NFT token ID of the derivative
    function registerDerivativeWithRoyalties(
        address derivativeRecipient,
        WorkflowStructs.IPMetadata calldata derivativeMetadata,
        WorkflowStructs.MakeDerivative calldata derivativeData,
        WorkflowStructs.RoyaltyShare[] calldata royaltyShares,
        bool allowDuplicates
    ) external returns (address childIpId, uint256 tokenId) {
        require(spgNftCollection != address(0), "Collection not created");

        // Validate royalty shares
        uint32 totalShares = 0;
        for (uint i = 0; i < royaltyShares.length; i++) {
            totalShares += royaltyShares[i].percentage;
        }
        require(totalShares == 100_000_000, "Royalty shares must sum to 100%");

        // Create derivative + distribute royalty tokens atomically
        (childIpId, tokenId) = royaltyDistributionWorkflows
            .mintAndRegisterIpAndMakeDerivativeAndDistributeRoyaltyTokens(
                spgNftCollection,
                derivativeRecipient,
                derivativeMetadata,
                derivativeData,
                royaltyShares,
                allowDuplicates
            );

        emit DerivativeCreated(
            childIpId,
            tokenId,
            derivativeData.parentIpIds[0],
            derivativeData.maxMintingFee
        );
    }

    ///@notice Claim accumulated royalties for an IP asset
    ///@dev Authors can claim their share of royalties from all derivative works
    ///@param ipId The IP Asset ID
    ///@param claimer The address claiming the royalties (must hold royalty tokens)
    ///@param claimRevenueData Array of data structures defining which revenues to claim from
    ///@return amountsClaimed Array of amounts claimed from each revenue source
    function claimRoyalties(
        address ipId,
        address claimer,
        WorkflowStructs.ClaimRevenueData[] calldata claimRevenueData
    ) external returns (uint256[] memory amountsClaimed) {
        // Anyone can trigger royalty claims (gas sponsor model)
        // LAP policy automatically distributes to royalty token holders

        amountsClaimed = royaltyWorkflows.claimAllRevenue(
            ipId,
            claimer,
            claimRevenueData
        );

        emit RoyaltiesClaimed(ipId, claimer, amountsClaimed);
    }

    ///@notice Helper to check if commercial license is included
    function _hasCommercialLicense(
        uint8[] calldata licenseTypes
    ) internal pure returns (bool) {
        for (uint i = 0; i < licenseTypes.length; i++) {
            if (licenseTypes[i] == 0) return true; // 0 = Commercial Remix
        }
        return false;
    }

    ///@notice Helper function to create license terms for multiple license types
    ///@param licenseTypes Array of license types
    ///@param customFee Custom fee for commercial licenses
    ///@param customRoyalty Custom royalty share for commercial licenses (in Story format: 5% = 5000000)
    function _getMultipleLicenseTerms(
        uint8[] calldata licenseTypes,
        uint256 customFee,
        uint32 customRoyalty
    ) internal returns (WorkflowStructs.LicenseTermsData[] memory) {
        WorkflowStructs.LicenseTermsData[]
            memory termsData = new WorkflowStructs.LicenseTermsData[](
                licenseTypes.length
            );

        for (uint i = 0; i < licenseTypes.length; i++) {
            PILTerms memory terms;

            if (licenseTypes[i] == 1) {
                // Non-Commercial Social Remixing
                terms = PILFlavors.nonCommercialSocialRemixing();
            } else if (licenseTypes[i] == 0) {
                // Commercial Remix
                uint256 feeToUse = customFee > 0 ? customFee : 10 * 10 ** 18; // Default $10
                uint32 royaltyToUse = customRoyalty > 0
                    ? customRoyalty
                    : 5000000; // Default 5%

                terms = PILFlavors.commercialRemix(
                    feeToUse,
                    royaltyToUse,
                    royaltyPolicyAddress, // LAP policy
                    supportedCurrency
                );
            } else {
                // Creative Commons Attribution
                terms = PILFlavors.creativeCommonsAttribution(
                    royaltyPolicyAddress,
                    supportedCurrency
                );
            }

            termsData[i] = WorkflowStructs.LicenseTermsData({
                terms: terms,
                licensingConfig: Licensing.LicensingConfig({
                    isSet: false,
                    mintingFee: 0,
                    licensingHook: address(0),
                    hookData: "",
                    commercialRevShare: 0,
                    disabled: false,
                    expectMinimumGroupRewardShare: 0,
                    expectGroupRewardPool: address(0)
                })
            });
        }

        return termsData;
    }

    ///@notice Emergency pause function
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // TODO:
    // - Review royalty payment to include platform fee 0.1%
    // - Add sponsored gas mechanism for book registration and non-commercial derivative creation
}
