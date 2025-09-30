//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {IRoyaltyTokenDistributionWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyTokenDistributionWorkflows.sol";
import {IDerivativeWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IDerivativeWorkflows.sol";
import {IRoyaltyWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRoyaltyWorkflows.sol";
import {IRoyaltyModule} from "@storyprotocol/core/interfaces/modules/royalty/IRoyaltyModule.sol";
import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {PILTerms} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {Licensing} from "@storyprotocol/core/lib/Licensing.sol";
import {PILFlavors} from "@storyprotocol/core/lib/PILFlavors.sol";

///@title BookIPRegistrationAndManagement.sol
///@notice Gateway contract for registering books as IP on Story Protocol with full royalty management.

contract BookIPRegistrationAndManagement is Ownable, Pausable {
    using SafeERC20 for IERC20;
    // State variables
    IRegistrationWorkflows public immutable registrationWorkflows;
    IRoyaltyTokenDistributionWorkflows
        public immutable royaltyDistributionWorkflows;
    IDerivativeWorkflows public immutable derivativeWorkflows;
    IRoyaltyWorkflows public immutable royaltyWorkflows;
    IRoyaltyModule public immutable royaltyModule;
    address public immutable pilTemplate;
    address public immutable supportedCurrency; // Wrapped $IP
    address public immutable royaltyPolicyAddress; // LAP Policy

    address public spgNftCollection;

    /// @notice Whitelisted authors (only they can register books)
    mapping(address => bool) public authorizedAuthors;

    /// @notice Platform fee on tips/royalty payments (basis points: 1000 = 0.1%)
    uint256 public appRoyaltyFeePercent;

    /// @dev Story Protocol uses 8 decimals for percentages (100_000_000 = 100%)
    uint32 private constant PERCENTAGE_SCALE = 100_000_000;

    /// @dev Default commercial remix license fee ($10 in 18 decimals)
    uint256 private constant DEFAULT_COMMERCIAL_FEE = 10 * 10 ** 18;

    /// @dev Default commercial remix royalty share (5% in Story format)
    uint32 private constant DEFAULT_COMMERCIAL_ROYALTY = 5_000_000;

    /// @dev Maximum number of collaborators (gas optimization threshold)
    uint256 private constant MAX_COLLABORATORS = 16; // Story Protocol limit for parent IPs

    // Events
    event BookCollectionCreated(address indexed collection);
    event BookRegistered(
        address indexed ipId,
        uint256 indexed tokenId,
        uint256[] indexed licenseTerms,
        address royaltyVault,
        uint256 numberOfAuthors
    );
    event DerivativeCreated(
        address indexed childIpId,
        uint256 indexed tokenId,
        address[] parentIpIds,
        uint256 totalLicensingFees
    );
    event RoyaltiesClaimed(
        address indexed ipId,
        address indexed claimer,
        address[] currencyTokens,
        uint256[] amounts
    );

    event TipPaid(
        address indexed ipId,
        address indexed tipper,
        uint256 tipAmount,
        uint256 platformFee,
        string message
    );

    event RoyaltySharePaid(
        address indexed receiverIpId,
        address indexed payerIpId,
        address indexed payer,
        uint256 amount,
        string reason
    );

    event AppFeeUpdated(uint256 oldFee, uint256 newFee);

    // ERRORS (Gas-Efficient Custom Errors)

    error InvalidAddress(string paramName);
    error CollectionAlreadyCreated();
    error CollectionNotCreated();
    error Unauthorized();
    error InvalidLicenseTypes();
    error InvalidAuthorData();
    error InvalidRoyaltyShares();
    error InvalidAmount();
    error NoRoyaltyVault();
    error TooManyCollaborators(uint256 provided, uint256 max);

    constructor(
        address initialOwner,
        address _registrationWorkflows,
        address _royaltyDistributionWorkflows,
        address _derivativeWorkflows,
        address _royaltyWorkflows,
        address _royaltyModule,
        address _pilTemplate,
        address _supportedCurrency,
        address _royaltyPolicyAddress
    ) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert InvalidAddress("initialOwner");
        if (_registrationWorkflows == address(0))
            revert InvalidAddress("registrationWorkflows");
        if (_royaltyDistributionWorkflows == address(0))
            revert InvalidAddress("royaltyDistributionWorkflows");
        if (_derivativeWorkflows == address(0))
            revert InvalidAddress("derivativeWorkflows");
        if (_royaltyWorkflows == address(0))
            revert InvalidAddress("royaltyWorkflows");
        if (_royaltyModule == address(0))
            revert InvalidAddress("royaltyModule");
        if (_pilTemplate == address(0)) revert InvalidAddress("pilTemplate");
        if (_supportedCurrency == address(0))
            revert InvalidAddress("supportedCurrency");
        if (_royaltyPolicyAddress == address(0))
            revert InvalidAddress("royaltyPolicyAddress");

        registrationWorkflows = IRegistrationWorkflows(_registrationWorkflows);
        royaltyDistributionWorkflows = IRoyaltyTokenDistributionWorkflows(
            _royaltyDistributionWorkflows
        );
        derivativeWorkflows = IDerivativeWorkflows(_derivativeWorkflows);
        royaltyWorkflows = IRoyaltyWorkflows(_royaltyWorkflows);
        royaltyModule = IRoyaltyModule(_royaltyModule);
        pilTemplate = _pilTemplate;
        supportedCurrency = _supportedCurrency;
        royaltyPolicyAddress = _royaltyPolicyAddress;

        appRoyaltyFeePercent = 1_000_000; // 1%
    }

    ///@notice Creates the SPGNFT collection for this application
    ///@param spgNftInitParams Initialization parameters for the collection
    function createBookCollection(
        ISPGNFT.InitParams calldata spgNftInitParams
    ) external onlyOwner whenNotPaused {
        if (spgNftCollection != address(0)) revert CollectionAlreadyCreated();
        if (bytes(spgNftInitParams.name).length == 0)
            revert InvalidAddress("name");
        if (spgNftInitParams.maxSupply == 0) revert InvalidAmount();
        if (spgNftInitParams.owner != address(this)) revert Unauthorized();

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

    ///@notice Update platform fee percentage
    ///@param newFeePercent New fee in Story format (1_000_000 = 1%)
    function setAppFee(uint256 newFeePercent) external onlyOwner {
        if (newFeePercent > 10_000_000) revert InvalidAmount(); // Max 10%
        uint256 oldFee = appRoyaltyFeePercent;
        appRoyaltyFeePercent = newFeePercent;
        emit AppFeeUpdated(oldFee, newFeePercent);
    }

    ///@notice Register a book as root IP asset with royalty token distribution
    ///@dev Supports both single and multiple authors with automatic share calculation
    ///@param recipient The recipient of the NFT (typically the main atuhor)
    ///@param ipMetadata Metadata for the IP Asset (the book)
    ///@param licenseTypes Array of license types to attach (0: Commercial Remix, 1: Non-Commercial Remix, 2: Creative Commons)
    ///@param customCommercialFee Custom fee for commercial license (0 = use default)
    ///@param customLicensorRoyaltyShare Custom royalty share for commercial license (0 = use default)
    ///@param royaltyShares Royalty distribution for single author (ignored if authors.length > 1)
    ///@param authors Array of author addresses
    ///@param authorShares Array of shares for each author (must sum to 100_000_000)
    ///@param allowDuplicates Whether to allow duplicate metadata
    ///@return ipId The registered IP Asset ID
    ///@return tokenId the NFT token ID
    ///@return licenseTermsIds The attached license term IDs
    function registerBook(
        address recipient,
        WorkflowStructs.IPMetadata calldata ipMetadata,
        uint8[] calldata licenseTypes,
        uint256 customCommercialFee,
        uint32 customLicensorRoyaltyShare,
        WorkflowStructs.RoyaltyShare[] calldata royaltyShares,
        address[] calldata authors,
        uint256[] calldata authorShares,
        bool allowDuplicates
    )
        external
        whenNotPaused
        returns (
            address ipId,
            uint256 tokenId,
            uint256[] memory licenseTermsIds
        )
    {
        if (spgNftCollection == address(0)) revert CollectionNotCreated();
        if (!authorizedAuthors[msg.sender] && msg.sender != owner())
            revert Unauthorized();
        if (licenseTypes.length == 0 || licenseTypes.length > 3)
            revert InvalidLicenseTypes();

        // Validate license types
        for (uint256 i = 0; i < licenseTypes.length; ++i) {
            if (licenseTypes[i] > 2) revert InvalidLicenseTypes();
        }

        // License Terms Construction
        WorkflowStructs.LicenseTermsData[]
            memory licenseTermsData = _buildLicenseTermsData(
                licenseTypes,
                customCommercialFee,
                customLicensorRoyaltyShare
            );

        // Multi-author handling
        WorkflowStructs.RoyaltyShare[] memory finalRoyaltyShares;

        if (authors.length > 1) {
            // Multiple authors: process and validate shares
            finalRoyaltyShares = _processMultipleAuthors(authors, authorShares);
        } else if (authors.length == 1) {
            // Single author via authors array: create simple share
            finalRoyaltyShares = new WorkflowStructs.RoyaltyShare[](1);
            finalRoyaltyShares[0] = WorkflowStructs.RoyaltyShare({
                recipient: authors[0],
                percentage: PERCENTAGE_SCALE // 100%
            });
        } else {
            // Single author via royaltyShares parameter: validate sum
            _validateRoyaltySharesSum(royaltyShares);
            finalRoyaltyShares = royaltyShares;
        }

        // Story Protocol Registration
        (ipId, tokenId, licenseTermsIds) = royaltyDistributionWorkflows
            .mintAndRegisterIpAndAttachPILTermsAndDistributeRoyaltyTokens(
                spgNftCollection,
                recipient,
                ipMetadata,
                licenseTermsData,
                finalRoyaltyShares,
                allowDuplicates
            );

        // Event emission
        address royaltyVault = royaltyModule.ipRoyaltyVaults(ipId);
        emit BookRegistered(
            ipId,
            tokenId,
            licenseTermsIds,
            royaltyVault,
            finalRoyaltyShares.length
        );
    }

    ///@notice Register derivative with custom royalty distribution
    ///@dev Supports collaborative derivatives with flexible share allocation
    ///@param derivativeRecipient Recipient of the derivative NFT
    ///@param parentIpIds Array of parent IP IDs (max 16)
    ///@param licenseTermsIds License term IDs for each parent
    ///@param derivativeMetadata Metadata for derivative
    ///@param royaltyShares Single-author distribution (ignored if authors provided)
    ///@param authors Multiple authors (empty = use royaltyShares)
    ///@param authorShares Shares for each author
    ///@param maxMintingFee Maximum acceptable minting fee
    ///@param maxRts Maximum royalty tokens
    ///@param maxRevenueShare Maximum revenue share
    ///@param allowDuplicates Allow duplicate metadata
    ///@return childIpId Derivative IP ID
    ///@return tokenId Derivative token ID
    function registerDerivative(
        address derivativeRecipient,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds,
        WorkflowStructs.IPMetadata calldata derivativeMetadata,
        WorkflowStructs.RoyaltyShare[] calldata royaltyShares,
        address[] calldata authors,
        uint256[] calldata authorShares,
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

        // Create derivative data structure
        WorkflowStructs.MakeDerivative memory derivativeData = WorkflowStructs
            .MakeDerivative({
                parentIpIds: parentIpIds,
                licenseTermsIds: licenseTermsIds,
                licenseTemplate: pilTemplate,
                royaltyContext: "", // Empty for LAP policy
                maxMintingFee: maxMintingFee,
                maxRts: maxRts,
                maxRevenueShare: maxRevenueShare
            });

        if (authors.length > 1) {
            // Split royalty shares among multiple authors
            WorkflowStructs.RoyaltyShare[]
                memory complexRoyaltyShares = new WorkflowStructs.RoyaltyShare[](
                    authors.length + 1
                );
            uint32 totalAuthorShare = 0;
            for (uint i = 0; i < authors.length; i++) {
                require(authors[i] != address(0), "Invalid author address");
                require(authorShares[i] > 0, "Author share must be positive");
                totalAuthorShare += uint32(authorShares[i]);
                complexRoyaltyShares[i] = WorkflowStructs.RoyaltyShare({
                    recipient: authors[i],
                    percentage: uint32(authorShares[i])
                });
            }
            require(
                totalAuthorShare <= 100_000_000,
                "Total author share too high"
            );

            // Create derivative with custom royalty token distribution for multiple authors
            (childIpId, tokenId) = royaltyDistributionWorkflows
                .mintAndRegisterIpAndMakeDerivativeAndDistributeRoyaltyTokens(
                    spgNftCollection,
                    derivativeRecipient,
                    derivativeMetadata,
                    derivativeData,
                    complexRoyaltyShares,
                    allowDuplicates
                );
        } else {
            // Validate royalty shares sum to 100%
            uint32 totalShares = 0;
            for (uint i = 0; i < royaltyShares.length; i++) {
                totalShares += royaltyShares[i].percentage;
            }
            require(
                totalShares == 100_000_000,
                "Royalty shares must sum to 100"
            );

            // Create derivative with custom royalty token distribution for single author
            (childIpId, tokenId) = royaltyDistributionWorkflows
                .mintAndRegisterIpAndMakeDerivativeAndDistributeRoyaltyTokens(
                    spgNftCollection,
                    derivativeRecipient,
                    derivativeMetadata,
                    derivativeData,
                    royaltyShares,
                    allowDuplicates
                );
        }

        emit DerivativeCreated(
            childIpId,
            tokenId,
            parentIpIds[0],
            maxMintingFee
        );
    }

    ///@notice Claim accumulated royalties for an IP asset
    ///@dev Authors can claim their share of royalties from all derivative works
    ///@param ipId The IP Asset ID
    ///@param claimer The address claiming the royalties. Only royalty token holders can claim, and only for their proportional share.
    ///@param claimRevenueData Array of data structures defining which revenues to claim from
    ///@return amountsClaimed Array of amounts claimed from each revenue source
    function claimRoyalties(
        address ipId,
        address claimer,
        WorkflowStructs.ClaimRevenueData[] calldata claimRevenueData
    ) external returns (uint256[] memory amountsClaimed) {
        amountsClaimed = royaltyWorkflows.claimAllRevenue(
            ipId,
            claimer,
            claimRevenueData
        );

        emit RoyaltiesClaimed(ipId, claimer, amountsClaimed);
    }

    ///@notice Pay royalties on-chain (for derivative owners acknowledging parent IP)
    ///@param parentIpId The parent IP to pay royalties to
    ///@param derivativeIpId The derivative that's paying (for tracking)
    ///@param amount Amount to pay
    ///@param reason Reason for payment ("quarterly royalties", "goodwill payment", etc.)
    function payRoyaltyShare(
        address parentIpId,
        address derivativeIpId,
        uint256 amount,
        string calldata reason
    ) external {
        require(amount > 0, "Payment must be positive");
        require(
            IRoyaltyModule(royaltyModule).ipRoyaltyVaults(parentIpId) !=
                address(0),
            "Parent IP has no royalty vault"
        );

        IRoyaltyModule(royaltyModule).payRoyaltyOnBehalf(
            parentIpId,
            derivativeIpId,
            supportedCurrency,
            amount
        );

        emit RoyaltySharePaid(
            parentIpId,
            derivativeIpId,
            msg.sender,
            amount,
            reason
        );
    }

    ///@notice Pay tip directly to a root asset (book)
    ///@param ipId The IP asset to tip
    ///@param amount Amount to tip in supported currency
    ///@param message Optional tip message
    function payTip(
        address ipId,
        uint256 amount,
        string calldata message
    ) external {
        require(amount > 0, "Tip must be positive");

        // App takes small fee from tips too
        uint256 appFee = (amount * appRoyaltyFeePercent) / 100_000_000;
        uint256 tipAmount = amount - appFee;

        // Pay tip directly to IP owner (bypasses royalty policies)
        IERC20(supportedCurrency).transferFrom(msg.sender, ipId, tipAmount);

        // Keep dApp fee
        IERC20(supportedCurrency).transferFrom(
            msg.sender,
            address(this),
            appFee
        );

        emit TipPaid(ipId, msg.sender, tipAmount, message);
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
}
