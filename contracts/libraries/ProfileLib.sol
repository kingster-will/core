// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {GeneralHelpers} from './helpers/GeneralHelpers.sol';
import {MetaTxHelpers} from './helpers/MetaTxHelpers.sol';
import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';
import {Events} from './Events.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import './Constants.sol';

library ProfileLib {
    /**
     * @notice Creates a profile with the given parameters to the given address. Minting happens
     * in the hub.
     *
     * @param vars The CreateProfileData struct containing the following parameters:
     *      to: The address receiving the profile.
     *      imageURI: The URI to set for the profile image.
     *      followModule: The follow module to use, can be the zero address.
     *      followModuleInitData: The follow module initialization data, if any
     *      followNFTURI: The URI to set for the follow NFT.
     * @param profileId The profile ID to associate with this profile NFT (token ID).
     */
    function createProfile(DataTypes.CreateProfileData calldata vars, uint256 profileId) external {
        _validateProfileCreatorWhitelisted();

        if (bytes(vars.imageURI).length > MAX_PROFILE_IMAGE_URI_LENGTH)
            revert Errors.ProfileImageURILengthInvalid();

        _setProfileString(profileId, PROFILE_IMAGE_URI_OFFSET, vars.imageURI);
        _setProfileString(profileId, PROFILE_FOLLOW_NFT_URI_OFFSET, vars.followNFTURI);

        bytes memory followModuleReturnData;
        if (vars.followModule != address(0)) {
            // Load the follow module to be used in the next assembly block.
            address followModule = vars.followModule;

            // Store the follow module for the new profile. We opt not to use the
            // _setFollowModule() private function to avoid unnecessary checks.
            assembly {
                mstore(0, profileId)
                mstore(32, PROFILE_BY_ID_MAPPING_SLOT)
                let slot := add(keccak256(0, 64), PROFILE_FOLLOW_MODULE_OFFSET)
                sstore(slot, followModule)
            }

            // @note We don't need to check for deprecated modules here because deprecated modules
            // are no longer whitelisted.
            // Initialize the follow module.
            followModuleReturnData = _initFollowModule(
                profileId,
                vars.to,
                vars.followModule,
                vars.followModuleInitData
            );
        }
        emit Events.ProfileCreated(
            profileId,
            msg.sender,
            vars.to,
            vars.imageURI,
            vars.followModule,
            followModuleReturnData,
            vars.followNFTURI,
            block.timestamp
        );
    }

    /**
     * @notice Sets the profile image URI for a given profile.
     *
     * @param profileId The profile ID.
     * @param imageURI The image URI to set.

     */
    function setProfileImageURI(uint256 profileId, string calldata imageURI) external {
        GeneralHelpers.validateCallerIsOwnerOrDispatcherOrExecutor(profileId);
        _setProfileImageURI(profileId, imageURI);
    }

    /**
     * @notice Sets the profile image URI via signature for a given profile.
     *
     * @param vars the SetProfileImageURIWithSigData struct containing the relevant parameters.
     */
    function setProfileImageURIWithSig(DataTypes.SetProfileImageURIWithSigData calldata vars)
        external
    {
        uint256 profileId = vars.profileId;
        address signer = GeneralHelpers.getOriginatorOrDelegatedExecutorSigner(
            GeneralHelpers.unsafeOwnerOf(profileId),
            vars.delegatedSigner
        );
        MetaTxHelpers.baseSetProfileImageURIWithSig(signer, vars);
        _setProfileImageURI(vars.profileId, vars.imageURI);
    }

    /**
     * @notice Sets the follow NFT URI for a given profile.
     *
     * @param profileId The profile ID.
     * @param followNFTURI The follow NFT URI to set.
     */
    function setFollowNFTURI(uint256 profileId, string calldata followNFTURI) external {
        GeneralHelpers.validateCallerIsOwnerOrDispatcherOrExecutor(profileId);
        _setFollowNFTURI(profileId, followNFTURI);
    }

    /**
     * @notice Sets the follow NFT URI via signature for a given profile.
     *
     * @param vars the SetFollowNFTURIWithSigData struct containing the relevant parameters.
     */
    function setFollowNFTURIWithSig(DataTypes.SetFollowNFTURIWithSigData calldata vars) external {
        uint256 profileId = vars.profileId;
        address signer = GeneralHelpers.getOriginatorOrDelegatedExecutorSigner(
            GeneralHelpers.unsafeOwnerOf(profileId),
            vars.delegatedSigner
        );
        MetaTxHelpers.baseSetFollowNFTURIWithSig(signer, vars);
        _setFollowNFTURI(vars.profileId, vars.followNFTURI);
    }

    /**
     * @notice Sets the follow module for a given profile.
     *
     * @param profileId The profile ID to set the follow module for.
     * @param followModule The follow module to set for the given profile, if any.
     * @param followModuleInitData The data to pass to the follow module for profile initialization.
     */
    function setFollowModule(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData
    ) external {
        GeneralHelpers.validateCallerIsOwnerOrDispatcherOrExecutor(profileId);
        _setFollowModule(profileId, msg.sender, followModule, followModuleInitData);
    }

    /**
     * @notice Sets the dispatcher for a given profile via signature.
     *
     * @param vars the setDispatcherWithSigData struct containing the relevant parameters.
     */
    function setDispatcherWithSig(DataTypes.SetDispatcherWithSigData calldata vars) external {
        MetaTxHelpers.baseSetDispatcherWithSig(vars);
        uint256 profileId = vars.profileId;
        address dispatcher = vars.dispatcher;

        // Store the dispatcher in the appropriate slot for the given profile ID.
        assembly {
            mstore(0, profileId)
            mstore(32, DISPATCHER_BY_PROFILE_MAPPING_SLOT)
            let slot := keccak256(0, 64)
            sstore(slot, dispatcher)
        }
        emit Events.DispatcherSet(profileId, dispatcher, block.timestamp);
    }

    /**
     * @notice sets the follow module via signature for a given profile.
     *
     * @param vars the SetFollowModuleWithSigData struct containing the relevant parameters.
     */
    function setFollowModuleWithSig(DataTypes.SetFollowModuleWithSigData calldata vars) external {
        uint256 profileId = vars.profileId;
        address signer = GeneralHelpers.getOriginatorOrDelegatedExecutorSigner(
            GeneralHelpers.unsafeOwnerOf(profileId),
            vars.delegatedSigner
        );
        MetaTxHelpers.baseSetFollowModuleWithSig(signer, vars);
        _setFollowModule(vars.profileId, signer, vars.followModule, vars.followModuleInitData);
    }

    function setProfileMetadataURI(uint256 profileId, string calldata metadataURI) external {
        GeneralHelpers.validateCallerIsOwnerOrDispatcherOrExecutor(profileId);
        _setProfileMetadataURI(profileId, metadataURI);
    }

    function setProfileMetadataURIWithSig(DataTypes.SetProfileMetadataURIWithSigData calldata vars)
        external
    {
        uint256 profileId = vars.profileId;
        address signer = GeneralHelpers.getOriginatorOrDelegatedExecutorSigner(
            GeneralHelpers.unsafeOwnerOf(profileId),
            vars.delegatedSigner
        );
        MetaTxHelpers.baseSetProfileMetadataURIWithSig(signer, vars);
        _setProfileMetadataURI(vars.profileId, vars.metadataURI);
    }

    function _setProfileString(
        uint256 profileId,
        uint256 profileOffset,
        string calldata value
    ) private {
        assembly {
            let length := value.length
            let cdOffset := value.offset
            mstore(0, profileId)
            mstore(32, PROFILE_BY_ID_MAPPING_SLOT)
            let slot := add(keccak256(0, 64), profileOffset)

            // If the length is greater than 31, storage rules are different.
            switch gt(length, 31)
            case 1 {
                // The length is > 31, so we need to store the actual string in a new slot,
                // equivalent to keccak256(startSlot), and store length*2+1 in startSlot.
                sstore(slot, add(shl(1, length), 1))

                // Calculate the amount of storage slots we need to store the full string.
                // This is equivalent to (string.length + 31)/32.
                let totalStorageSlots := shr(5, add(length, 31))

                // Compute the slot where the actual string will begin, which is the keccak256
                // hash of the slot where we stored the modified length.
                mstore(0, slot)
                slot := keccak256(0, 32)

                // Write the actual string to storage starting at the computed slot.
                // prettier-ignore
                for { let i := 0 } lt(i, totalStorageSlots) { i := add(i, 1) } {
                    sstore(add(slot, i), calldataload(add(cdOffset, mul(32, i))))
                }
            }
            default {
                // The length is <= 31 so store the string and the length*2 in the same slot.
                sstore(slot, or(calldataload(cdOffset), shl(1, length)))
            }
        }
    }

    function _setProfileMetadataURI(uint256 profileId, string calldata metadataURI) private {
        assembly {
            let length := metadataURI.length
            let cdOffset := metadataURI.offset
            mstore(0, profileId)
            mstore(32, PROFILE_METADATA_MAPPING_SLOT)
            let slot := keccak256(0, 64)

            // If the length is greater than 31, storage rules are different.
            switch gt(length, 31)
            case 1 {
                // The length is > 31, so we need to store the actual string in a new slot,
                // equivalent to keccak256(startSlot), and store length*2+1 in startSlot.
                sstore(slot, add(shl(1, length), 1))

                // Calculate the amount of storage slots we need to store the full string.
                // This is equivalent to (string.length + 31)/32.
                let totalStorageSlots := shr(5, add(length, 31))

                // Compute the slot where the actual string will begin, which is the keccak256
                // hash of the slot where we stored the modified length.
                mstore(0, slot)
                slot := keccak256(0, 32)

                // Write the actual string to storage starting at the computed slot.
                // prettier-ignore
                for { let i := 0 } lt(i, totalStorageSlots) { i := add(i, 1) } {
                    sstore(add(slot, i), calldataload(add(cdOffset, mul(32, i))))
                }
            }
            default {
                // The length is <= 31 so store the string and the length*2 in the same slot.
                sstore(slot, or(calldataload(cdOffset), shl(1, length)))
            }
        }
        emit Events.ProfileMetadataSet(profileId, metadataURI, block.timestamp);
    }

    function _setFollowModule(
        uint256 profileId,
        address executor,
        address followModule,
        bytes calldata followModuleInitData
    ) private {
        // Store the follow module in the appropriate slot for the given profile ID, but
        // only if it is not the same as the previous follow module.
        assembly {
            mstore(0, profileId)
            mstore(32, PROFILE_BY_ID_MAPPING_SLOT)
            let slot := add(keccak256(0, 64), PROFILE_FOLLOW_MODULE_OFFSET)
            let currentFollowModule := sload(slot)
            if iszero(eq(followModule, currentFollowModule)) {
                sstore(slot, followModule)
            }
        }

        // Initialize the follow module if it is non-zero.
        bytes memory followModuleReturnData;
        if (followModule != address(0))
            followModuleReturnData = _initFollowModule(
                profileId,
                executor,
                followModule,
                followModuleInitData
            );
        emit Events.FollowModuleSet(
            profileId,
            followModule,
            followModuleReturnData,
            block.timestamp
        );
    }

    function _initFollowModule(
        uint256 profileId,
        address executor,
        address followModule,
        bytes memory followModuleInitData
    ) private returns (bytes memory) {
        _validateFollowModuleWhitelisted(followModule);
        return
            IFollowModule(followModule).initializeFollowModule(
                profileId,
                executor,
                followModuleInitData
            );
    }

    function _setProfileImageURI(uint256 profileId, string calldata imageURI) private {
        if (bytes(imageURI).length > MAX_PROFILE_IMAGE_URI_LENGTH)
            revert Errors.ProfileImageURILengthInvalid();
        _setProfileString(profileId, PROFILE_IMAGE_URI_OFFSET, imageURI);
        emit Events.ProfileImageURISet(profileId, imageURI, block.timestamp);
    }

    function _setFollowNFTURI(uint256 profileId, string calldata followNFTURI) private {
        _setProfileString(profileId, PROFILE_FOLLOW_NFT_URI_OFFSET, followNFTURI);
        emit Events.FollowNFTURISet(profileId, followNFTURI, block.timestamp);
    }

    function _validateFollowModuleWhitelisted(address followModule) private view {
        bool whitelist;

        // Load whether the given follow module is whitelisted.
        assembly {
            mstore(0, followModule)
            mstore(32, FOLLOW_MODULE_WHITELIST_MAPPING_SLOT)
            let slot := keccak256(0, 64)
            whitelist := sload(slot)
        }
        if (!whitelist) revert Errors.FollowModuleNotWhitelisted();
    }

    function _validateProfileCreatorWhitelisted() private view {
        bool whitelisted;

        // Load whether the caller is whitelisted as a profile creator.
        assembly {
            mstore(0, caller())
            mstore(32, PROFILE_CREATOR_WHITELIST_MAPPING_SLOT)
            let slot := keccak256(0, 64)
            whitelisted := sload(slot)
        }
        if (!whitelisted) revert Errors.ProfileCreatorNotWhitelisted();
    }
}
