//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {ILicenseAttachmentWorkflows} from "@storyprotocol/periphery/interfaces/workflows/ILicenseAttachmentWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {Licensing} from "@storyprotocol/core/lib/Licensing.sol";
import {PILFlavors} from "@storyprotocol/core/lib/PILFlavors.sol";

///@title BookIPRegistrationAndManagement.sol
///@notice Gateway contract for registering books as IP on Story Protocol.
///@dev Provides gas-sponsored registration and derivative management for literary works.

contract BookIPRegistrationAndManagement is Ownable, Pausable {
    // State variables
    IRegistrationWorkflows public immutable registrationWorkflows;
    ILicenseAttachmentWorkflows public immutable licenseAttachmentWorkflows;
    IDerivativeWorkflows public immutable derivativeWorkflows;
    address public spgNftCollection;

    // PIL Template and supported currency
    address public immutable pilTemplate;
    address public immutable supportedCurrency; // Wrapped $IP
    address public immutable royaltyPolicyAddress;

    // Whitelisting
    mapping(address => bool) public authorizedAuthors;

    // Custom license fees (ipId => fee in wei)
    mapping(address => uint256) public customLicenseFees;

    // Events
    event BookCollectionCreated(address indexed collection);
    event BookRegistered(
        address indexed ipId,
        uint256 indexed tokenId,
        uint256[] indexed licenseTerms
    );
    event DerivativeCreated(
        address indexed childIpId,
        uint256 indexed tokenId,
        address indexed parentIpId
    );
    event CustomLicenseFeeSet(address indexed ipId, uint256 fee);

    constructor(
        address initialOwner,
        address _registrationWorkflows,
        address _licenseAttachmentWorkflows,
        address _derivativeWorkflows,
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
            _licenseAttachmentWorkflows != address(0),
            "Invalid LicenseAttachmentWorkflows address"
        );
        require(
            _derivativeWorkflows != address(0),
            "Invalid DerivativeWorkflows address"
        );
        require(_pilTemplate != address(0), "Invalid PIL template address");
        require(_supportedCurrency != address(0), "Invalid currency address");
        require(
            _royaltyPolicyAddress != address(0),
            "Invalid royalty policy address"
        );

        registrationWorkflows = IRegistrationWorkflows(_registrationWorkflows);
        licenseAttachmentWorkflows = ILicenseAttachmentWorkflows(
            _licenseAttachmentWorkflows
        );
        derivativeWorkflows = IDerivativeWorkflows(_derivativeWorkflows);
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

    ///@notice Whitelist an author
    ///@param author The author's address
    ///@param authorized True to whitelist, false to remove
    function setAuthorized(address author, bool authorized) external onlyOwner {
        authorizedAuthors[author] = authorized;
    }

    ///@notice Register a book as original IP with gas sponsoring
    ///@param recipient The recipient of the IP Asset (the author)
    ///@param ipMetadata Metadata for the IP Asset (the book)
    ///@param licenseType Type of license (0: Commercial Remix, 1: Non-Commercial Remix, 2: Creative Commons)
    ///@param customCommercialFee Custom fee for commercial license (only used if licenseType == 1)
    ///@param customRoyaltyShare Custom royalty share percentage (only used if licenseType == 1)
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return ipId The IP Asset ID
    ///@return tokenId the NFT token ID
    ///@return licenseTermsIds The IDs of the license terms attached to the IP Asset
    function registerBookWithSponsoredGas(
        address recipient,
        WorkflowStructs.IPMetadata calldata ipMetadata,
        uint8 licenseType,
        uint256 customCommercialFee,
        uint32 customRoyaltyShare,
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
        require(licenseType <= 2, "Invalid license type");

        // TODO: Implement gas sponsoring logic here
        // This could be done through meta-transactions or by the contract paying

        // Get the appropriate license terms based on type
        WorkflowStructs.LicenseTermsData[]
            memory licenseTermsData = _getLicenseTermsForType(
                licenseType,
                customCommercialFee,
                customRoyaltyShare
            );

        // Mint NFT, register IP, attach license terms, and tranfer to recipient
        (ipId, tokenId, licenseTermsIds) = licenseAttachmentWorkflows
            .mintAndRegisterIpAndAttachPILTerms(
                spgNftCollection,
                recipient,
                ipMetadata,
                licenseTermsData,
                allowDuplicates
            );

        // Store custom fee if it's a commercial license
        if (licenseType == 0 && customCommercialFee > 0) {
            customLicenseFees[ipId] = customCommercialFee;
            emit CustomLicenseFeeSet(ipId, customCommercialFee);
        }

        emit BookRegistered(ipId, tokenId, licenseTermsIds);
    }

    ///@notice Register a derivative work using direct licensing (user pays fees)
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
        require(msg.sender == owner(), "Only owner can register derivatives");
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

        // The user must have approved this contract to spend their tokens for fees
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

        emit DerivativeCreated(childIpId, tokenId, parentIpIds[0]);
    }

    ///@notice Internal function to get license terms based on type using PIL Flavors
    ///@param licenseType 0: Commercial Remix, 1: Non-Commercial Remix, 2: Creative Commons
    ///@param customFee Custom fee for commercial licenses
    ///@param customRoyalty Custom royalty share for commercial licenses (in Story format: 5% = 5000000)
    function _getLicenseTermsForType(
        uint8 licenseType,
        uint256 customFee,
        uint32 customRoyalty
    ) internal returns (WorkflowStructs.LicenseTermsData[] memory) {
        WorkflowStructs.LicenseTermsData[]
            memory termsData = new WorkflowStructs.LicenseTermsData[](1);
        PILTerms memory terms;

        if (licenseType == 1) {
            // Use PIL Flavor: Non-Commercial Social Remixing
            terms = PILFlavors.nonCommercialSocialRemixing();
        } else if (licenseType == 0) {
            // Use PIL Flavor: Commercial Remix with custom fee/royalty
            uint256 feeToUse = customFee > 0 ? customFee : 10 * 10 ** 18; // Default IP$10
            uint32 royaltyToUse = customRoyalty > 0 ? customRoyalty : 5000000; // Default 5% (5 * 10^6)

            terms = PILFlavors.commercialRemix(
                feeToUse,
                royaltyToUse,
                royaltyPolicyAddress,
                supportedCurrency
            );
        } else {
            // Use PIL Flavor: Creative Commons Attribution
            terms = PILFlavors.creativeCommonsAttribution(
                royaltyPolicyAddress,
                supportedCurrency
            );
        }

        // Use default licensing config (no overrides)
        Licensing.LicensingConfig memory config = Licensing.LicensingConfig({
            isSet: false, // Use PIL terms defaults
            mintingFee: 0,
            licensingHook: address(0),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        termsData[0] = WorkflowStructs.LicenseTermsData({
            terms: terms,
            licensingConfig: config
        });

        return termsData;
    }

    ///@notice Emergency pause function
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // TODO: Add functions for:
    // - Royalty payment and distribution. Include logic to pay a fee to the dApp
    // - Claiming royalties
    // - Setting PIL terms IDs after deployment
}
