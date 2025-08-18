//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Pausable } from '@openzeppelin/contracts/utils/Pausable.sol';
//import { ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { ISPGNFT } from '@storyprotocol/periphery/interfaces/ISPGNFT.sol';
import { IRegistrationWorkflows } from '@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol';
import { ILicenseAttachmentWorkflows } from '@storyprotocol/periphery/interfaces/workflows/ILicenseAttachmentWorkflows.sol';
import { IDerivativeWorkflows } from '@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol';
import { WorkflowStructs } from '@storyprotocol/periphery/lib/WorkflowStructs.sol';

///@title BookGateway.sol
///@notice Gateway contract for registering books as IP on Story Protocol.
///@dev Provides gas-sponsored registration and derivative management for literary works.

contract BookGateway is Ownable, Pausable {
    
    // State variables
    IRegistrationWorkflows public immutable registrationWorkflows;
    ILicenseAttachmentWorkflows public immutable licenseAttachmentWorkflows;
    IDerivativeWorkflows public immutable derivativeWorkflows;
    address public spgNftCollection;

    // PIL Terms IDs for the three supported license types
    uint256 public commercialRemixTermsId;
    uint256 public nonCommercialRemixTermsId;
    uint256 public commonAttributionTermsId;

    // Whitelisting
    mapping(address => bool) public authorizedAuthors;

    // Events
    event BookCollectionCreated(address indexed collection);
    event BookRegistered(address indexed ipId, uint256 indexed tokenId, uint256[] indexed licenseTerms);
    event DerivativeCreated(address indexed childIpId, uint256 indexed tokenId);

    constructor(
        address initialOwner,
        address _registrationWorkflows,
        address _licenseAttachmentWorkflows,
        address _derivativeWorkflows) Ownable(initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero address");
        require(_registrationWorkflows != address(0), "Invalid RegistrationWorkflows address");
        require(_licenseAttachmentWorkflows != address(0), "Invalid LicenseAttachmentWorkflows address");
        require(_derivativeWorkflows != address(0), "Invalid DerivativeWorkflows address");

        registrationWorkflows = IRegistrationWorkflows(_registrationWorkflows);
        licenseAttachmentWorkflows = ILicenseAttachmentWorkflows(_licenseAttachmentWorkflows);
        derivativeWorkflows = IDerivativeWorkflows(_derivativeWorkflows);
    }

    ///@notice Creates the SPGNFT collection for books
    ///@param spgNftInitParams Initialization parameters for the collection
    function createBookCollection(ISPGNFT.InitParams calldata spgNftInitParams) external onlyOwner whenNotPaused {
        require(spgNftCollection == address(0), "Collection already created");
        require(bytes(spgNftInitParams.name).length > 0, "Name required");
        require(spgNftInitParams.maxSupply > 0, "Invalid max supply");
        require(spgNftInitParams.owner == address(this), "Owner must be this contract");

        spgNftCollection = registrationWorkflows.createCollection(spgNftInitParams);
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
    ///@param licenseType Type of license (0: Commercial Remix, 1: Non-Commercial Remix, 2: Common Attribution)
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return ipId The IP Asset ID
    ///@return tokenId the NFT token ID
    ///@return licenseTermsIds The IDs of the license terms attached to the IP Asset
    function registerBookWithSponsoredGas(
        address recipient,
        WorkflowStructs.IPMetadata calldata ipMetadata,
        uint8 licenseType,
        bool allowDuplicates
        ) external returns (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds) {
        require(spgNftCollection != address(0), "Collection not created");
        require(authorizedAuthors[msg.sender] || msg.sender == owner(), "Not authorized to register books");
        require(licenseType <= 2, "Invalid license type");

        // TODO: Implement gas sponsoring logic here
        // This could be done through meta-transactions or by the contract paying

        // Get the appropriate license terms based on type
        WorkflowStructs.LicenseTermsData[] memory licenseTermsData = _getLicenseTermsForType(licenseType);

        // Mint NFT, register IP, attach license terms, and tranfer to recipient
        (ipId, tokenId, licenseTermsIds) = licenseAttachmentWorkflows.mintAndRegisterIpAndAttachPILTerms(
            spgNftCollection,
            recipient,
            ipMetadata,
            licenseTermsData,
            allowDuplicates);

        emit BookRegistered(ipId, tokenId, licenseTermsIds);
    }

    ///@notice Register a derivative work
    ///@param derivativeRecipient Recipient of the derivative IP Asset
    ///@param parentIpId The parent IP Asset this derivative is based on
    ///@param derivativeMetadata Metadata for the derivative IP Asset
    ///@return childIpId The ID of the newly created derivative IP Asset
    ///@return tokenId The NFT token ID of the derivative
    function registerDerivative(
        address derivativeRecipient,
        address parentIpId,
        WorkflowStructs.IPMetadata calldata derivativeMetadata,
        bytes calldata royaltyContext,
        uint32 maxRts,
        bool allowDuplicates
        ) external returns (address childIpId, uint256 tokenId) {
        require(spgNftCollection != address(0), "Collection not created");
        require(msg.sender == owner(), "Only owner can register derivatives");

        WorkflowStructs.MakeDerivative[] memory licenseTermsIds = _getLicenseTermsIds(parentIpId);

        (childIpId, tokenId) = derivativeWorkflows.mintAndRegisterIpAndMakeDerivativeWithLicenseTokens(
            spgNftCollection,
            licenseTermsIds,
            royaltyContext,
            maxRts,
            derivativeMetadata,
            derivativeRecipient,
            allowDuplicates
        );
        
        require(childIpId != address(0), "Derivative creation failed");

        emit DerivativeCreated(childIpId, tokenId);
    }

    ///@notice Internal function to get license terms based on type
    ///@param licenseType 0: Commercial Remix, 1: Non-Commercial Remix, 2: Common Attribution
    function _getLicenseTermsForType(uint8 licenseType) internal view returns (WorkflowStructs.LicenseTermsData[] memory) {

        // TODO: Implement logic to return appropriate PIL terms
        // This will depend on your specific license configurations
        WorkflowStructs.LicenseTermsData[] memory termsData = new WorkflowStructs.LicenseTermsData[](1);

        // Example structure - fill in the actual PIL terms
        // termsData[0] = WorkflowStructs.LicenseTermsData({
        //     pilTerms: ..., // PIL terms struct
        //     licensingConfig: ... // licensing config
        // });

        return termsData;
    }

    ///@notice Internal function to get license terms IDs for a parent IPId
    ///@param parentIpId The parent IP Asset ID
    function _getLicenseTermsIds(address parentIpId) internal view returns (WorkflowStructs.MakeDerivative[] memory) {

        WorkflowStructs.MakeDerivative[] memory licenseTermsIds = new WorkflowStructs.MakeDerivative[](1);

        return licenseTermsIds;
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