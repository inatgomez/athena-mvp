//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { ISPGNFT } from '@storyprotocol/periphery/interfaces/ISPGNFT.sol';
import { IRegistrationWorkflows } from '@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol';
import { ILicenseAttachmentWorkflows } from '@storyprotocol/periphery/interfaces/workflows/ILicenseAttachmentWorkflows.sol';

///@title BookGateway.sol
///@notice This contract is a gateway to interact with Story Protocol periphery and core contracts. It creates a dApp to register a book as intellectual property and manage its licenses, derivatives, and other related functionalities.
///@dev This contract is part of the Athena project, which aims to provide a decentralized platform for managing intellectual property rights in the form of books and other literary works.

contract BookGateway is Ownable {
    
    //State variables
    IRegistrationWorkflows public registrationWorkflows;
    ILicenseAttachmentWorkflows public licenseAttachmentWorkflows;
    address public spgNftCollection;

    constructor(address initialOwner, address _registration, address _licenseAttach) Ownable(initialOwner) {
        registrationWorkflows = IRegistrationWorkflows(_registration);
        licenseAttachmentWorkflows = ILicenseAttachmentWorkflows(_licenseAttach);
    }

    ///@notice Function to create a one time SPGNFT collection for the dApp
    ///@param spgNftInitParams The initialization parameters for the SPGNFT collection
    function createBookCollection(ISPGNFT.InitParams calldata spgNftInitParams) external onlyOwner {
        require(spgNftCollection == address(0), "Collection already created");

        spgNftCollection = registrationWorkflows.createCollection(spgNftInitParams);
    }


    //function: license logic and royalty policy. Only 3 PIL flavor (commercial remix, non-commercial remix, and common attribution) are supported. Give default values, but let user override them in the UI.

    //function to sponsor gas for original assets registration

    //function so only whitelisted addresses can register books

    //function to mint a license, register an asset as a derivative, and transfer to author
    //derivatives can be non-commercial remix like an article, summary, or review, a commercial remix like a book, translation, or course, or a common use like inspiration for a new book

    //function to pay royalty to an asset and distribute to ancestors. Include logic to pay a fee to the dApp

    //function to claim royalties

}