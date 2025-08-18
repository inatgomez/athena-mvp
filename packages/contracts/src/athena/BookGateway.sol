//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Pausable } from '@openzeppelin/contracts/utils/Pausable.sol';
//import { ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { ISPGNFT } from '@storyprotocol/periphery/interfaces/ISPGNFT.sol';
import { IRegistrationWorkflows } from '@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol';
import { ILicenseAttachmentWorkflows } from '@storyprotocol/periphery/interfaces/workflows/ILicenseAttachmentWorkflows.sol';
import { WorkflowStructs } from '@storyprotocol/periphery/lib/WorkflowStructs.sol';

///@title BookGateway.sol
///@notice Gateway contract for registering books as IP on Story Protocol.
///@dev Provides gas-sponsored registration and derivative management for literary works.

contract BookGateway is Ownable, Pausable {
    
    // State variables
    IRegistrationWorkflows public immutable registrationWorkflows;
    ILicenseAttachmentWorkflows public immutable licenseAttachmentWorkflows;
    address public spgNftCollection;

    // PIL Terms IDs for the three supported license types
    uint256 public commercialRemixTermsId;
    uint256 public nonCommercialRemixTermsId;
    uint256 public commonAttributionTermsId;

    // Whitelisting
    mapping(address => bool) public authorizedAuthors;

    // Events
    event BookCollectionCreated(address indexed collection);
    event BookRegistered(address indexed ipId, uint256 indexed tokenId, address indexed author);
    event DerivativeCreated(address indexed childIpId, address indexed parentIpId);

    constructor(address initialOwner, address _registrationWorkflows, address _licenseAttachmentWorkflows) Ownable(initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero address");
        require(_registrationWorkflows != address(0), "Invalid RegistrationWorkflows address");
        require(_licenseAttachmentWorkflows != address(0), "Invalid LicenseAttachmentWorkflows address");

        registrationWorkflows = IRegistrationWorkflows(_registrationWorkflows);
        licenseAttachmentWorkflows = ILicenseAttachmentWorkflows(_licenseAttachmentWorkflows);
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
    function registerBookWithSponsoredGas(address recipient, WorkflowStructs.IPMetadata calldata ipMetadata, uint8 licenseType, bool allowDuplicates) external returns (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds) {
        require(spgNftCollection != address(0), "Collection not created");
        require(authorizedAuthors[msg.sender] || msg.sender == owner(), "Not authorized to register books");
        require(licenseType <= 2, "Invalid license type");

        // TODO: Implement gas sponsoring logic here
        // This could be done through meta-transactions or by the contract paying

        // Get the appropriate license terms based on type
        WorkflowStructs.LicenseTermsData[] memory licenseTermsData = _getLicenseTermsForType(licenseType);

        // Register IP and attach license terms
        (ipId, tokenId, licenseTermsIds) = licenseAttachmentWorkflows.mintAndRegisterIpAndAttachPILTerms(spgNftCollection, recipient, ipMetadata, licenseTermsData, allowDuplicates);

        emit BookRegistered(ipId, tokenId, recipient);
    }

    ///@notice Register a derivative work
    ///@param derivativeRecipient Recipient of the derivative IP Asset
    ///@param parentIpId The parent IP Asset this derivative is based on
    ///@param derivativeMetadata Metadata for the derivative IP Asset
    ///@param licenseType License type for the derivative. Inherits from parent IP
    ///@return childIpId The ID of the newly created derivative IP Asset
    ///@return tokenId The NFT token ID of the derivative
    function registerDerivative(address derivativeRecipient, address parentIpId, WorkflowStructs.IPMetadata calldata derivativeMetadata, uint8 licenseType) external returns (address childIpId, address tokenId) {
        require(spgNftCollection != address(0), "Collection not created");
        
        // TODO: Implement derivative registration logic
        // This involves checking parent licenses, minting derivative NFT, and linking

        emit DerivativeCreated(childIpId, parentIpId);
    }

    ///@notice Internal function to get license terms based on type
    ///@param licenseType 0: Commercial Remix, 1: Non-Commercial Remix, 2: Common Attribution
    function _getLicenseTermsForType(uint8 licenseType) internal view returns (WorkflowStructs.LicenseTermsData[] memory) {

        // TODO: Implement logic to return appropriate PIL terms
        // This will depend on your specific license configurations
        WorkflowStructs.LicenseTermsData[] memory termsData = new WorkflowStructs.LicenseTermsData[](1);

        // Example structure - you'll need to fill in the actual PIL terms
        // termsData[0] = WorkflowStructs.LicenseTermsData({
        //     pilTerms: ..., // Your PIL terms struct
        //     licensingConfig: ... // Your licensing config
        // });

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