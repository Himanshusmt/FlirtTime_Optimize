//
//  ViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import Foundation

enum Constants{
    
    enum AlertButtons {
        static let ok = "Ok"
        static let okay = "Okay"
        static let cancel = "Cancel"
        static let yes = "Yes"
        static let No = "No"
        static let save = "Save"
        static let retake = "Retake"
        static let discard = "Discard"
        static let skip = "Skip"
        static let completeProfile = "Complete profile"
        static let complete = "Complete"
        static let exploreApp = "Explore app"
        static let exitNow = "Exit now"
        static let yesDelete = "Yes delete"
        static let yesUnmatch = "Yes unmatch"
        static let yesDiscard = "Yes discard"
        static let clearChat = "Clear chat"
        static let block = "Block"
        static let next = "Next"
        static let finish = "Finish"
        static let continueButton = "Continue"
    }
    
    enum Internet {
        static let notAvailable = "Internet not available."
        static let internetCode = 1005
    }
    
    enum APIStatus {
        static let success:Bool = true
        static let unauthenticated = "Unauthenticated."
        static let invalidPhoneNumber = "Please enter a valid phone number"
        static let invalidEmailID = "The email field must be a valid email address."
    }
    
    enum JWTToken {
        static let expaire = "Your session has expired. Kindly log in again."
    }
    
    enum LoginOption {
        static let text = "Click to read Term of services and privacy policy"
        static let acceptenceText = "By continuing I accept flirt time’s"
        static let termsService = "Term of services"
        static let privacyPolicy = "Privacy Policy"
    }
    
    enum UserDetails{
        
        static let firstName = "Full Name"
        static let lastName = "Last Name"
        static let nickName = "Display Name"
        static let dob = "Date of Birth"
        static let gender = "Gender"
        static let aboutYou = "About you"
        static let aboutYouPlaceHolder = "Looking for your soulmate? Start by writing a bio.."
        
        static let note = "Note:"
        static let dateOfBirthNote = " Date of Birth once selected can not be change"
        static let genderNote = " Gender once selected can not be change"
        static let tellYourStoryNote = " Tell us your story! Craft a bio that makes you stand out"
        
    }
    
    enum EnterPhoneNumber {
        static let validPhoneNumber = "Please enter valid Phone Number"
        static let wrongPhoneNumber = "Please enter a valid contact number so your match can text you."
    }
    
    enum VerifiyOTP {
        static let enterOtp = "Please enter code we sent you on"
        static let didnotRecive = "Didn’t Receive Code? "
        static let resend = "RESEND"
        static let emptyOtp = "Please enter otp"
        static let validOtp = "Please enter valid otp"
        static let codeSentViaMesg = "Please enter the code we’ve sent to you via text"
        static let codeSentViaEmail = "Please enter the code we’ve sent to you via mail on"
    }
    
    enum CustomPopUp{
        static let birthDayText = "When’s your \n birthday"
        static let genderText = "What’s your \n Gender"
        static let picUploadFailed = "Picture \n upload failed"
        static let nudeContent = "Nude/explicit content is not allowed."
        static let uploadingPicture = "Uploading your \n picture"
        static let spiceUpMatch = "Let's spice up your \n matches!"
        static let betterMatch = "Want better \n matches?"
        static let leavingAlready = "Leaving already?"
    }
    
    enum gesture{
        static let pose = "Copy this pose and\ntake a "
        static let photo = "photo"
        static let privacyPolicy = "Privacy Policy"
        static let moreInfo = "For more info on how we use, retain and\nprotect your personal date please read our "
    }
    
    enum ProfileVerification {
        static let focusOnFace = "Focus on your face"
        static let startPosing = "Start posing as asked for"
        static let clickPhoto = "Click your photo"
    }
    
    enum Moment {
        static let blockMessage = "Are you sure you want to block "
    }
    
    enum AddMoment {
        static let deleteImage = "Are you sure you want to delete ?"
        static let discard = "Are you sure you want to discard this moment ?"
        static let placeholder = "Tell everyone what’s your post is about."
    }
    
    enum PostComment {
        static let placeholder = "Your Comment.."
    }
    
    enum Chat {
        static let placeholder = "Message"
        static let noChatFound = "No chats found"
        static let noCallFound = "No calls found"
        static let clearChat = "Clear this chat?"
        static let blockUser = "Block User?"
        static let unmatch = "Are you sure you want to unmatch "
        
    }
    
    enum Compliment {
        static let placeholder = "Send compliment"
    }
    
    enum EditProfile {
        static let note = "Note:"
        static let dragAndHold = " Hold and drag media to set image on match card and long press to delete"
    }
    
    enum HelpAndSupport {
        static let text1 = "You can also write to us on :"
        static let website = " Flirt time.love"
    }
    
    enum changeEmailPhone {
        static let note = "Note:"
        static let enterEmail = "Enter new email"
        static let emailDescription  = "We’ll send you a unique code once again to verify your new email"
        static let enterPhone = "Enter new number"
        static let phoneDecription = "We’ll send you a unique code once again to verify your new number"
        static let phone = "Enter the verification code that we have sent to "
        static let email = "Enter the verification code that we have sent to "
        static let uniqueCodetext = " we'll send a unique code to your registered email address "
    }
    
    
    enum logOut{
        static let logout = "Are you sure you want to logout?"
    }
    
    enum deleteAccount{
        static let delete = "Are you sure you want to Delete your account?"
        static let restore = "Your Profile has been deleted, Do you want to restore your account?"
    }
    
    enum apiConstant{
        static let device = "iOS"
    }
    enum imgAPINames{
        static let gestureDocumentImage = "guestureImage.jpg"
        static let profileImage = "profile_image"
        static let gestureSource = "compare_image"
        static let gestureImage = "gesture_image"
        static let avatarImage = "avatar_image"
        static let bannerImage = "banner_image"
        static let image = "image"
        static let chatImage = "image"
    }
    
    enum GenderWithID {
        
        static let male = "Male"
        static let female = "Female"
        static let other = "Other"
        
    }
    
    enum QuestionType {
        
        static let radio = "radio"
        static let checkbox = "checkbox"
        
    }
    enum QuestionOption {
        
        static let sexuality = "sexuality"
        static let height = "height"
        static let weight = "weight"
        static let eye_colour = "eyecolor"
        static let hair_colour = "haircolor"
        static let living = "living"
        static let children = "children"
        static let smoking = "smoking"
        static let drinking = "drinking"
        static let interests = "interest"
        static let mother_tongue = "mothertongue"
        static let relationship = "relationship"
        static let religion = "religion"
        static let education = "education"
    }
    
    enum ActionType {
        
        static let like = "like"
        static let dislike = "dislike"
        static let favorite = "favorite"
        static let nope = "nope"
        
    }
    
    enum SwipeDirectionType {
        
        static let left = "left"
        static let right = "right"
        static let up = "up"
        
    }
    
    enum PostCommentConstant {
        static let viewMoreReplies = "View more replies"
        static let viewMoreReply = "View more reply"
        static let hideReplies = "Hide replies"
        static let hideReply = "Hide reply"
    }
    
    enum OtherUserProfileImages {
        static let selectedProfile = "OtherProfile_Selected"
        static let unselectedProfile = "OtherProfile"
        static let selectedMoments = "Moments_selected"
        static let unselectedMoments = "Moments"
        
    }
    
    enum UserInteractionTypes {
        static let myFavorite = "myfavorite"
        static let favoriteYou = "favoriteyou"
        static let myLike = "mylike"
        static let likeYou = "likeyou"
        static let matches = "Matches"
        static let compliment = "Compliment"
    }
    
    enum ImageErrorTypes {
        static let errorBannerImage = "Banner"
        static let errorUserImage = "UserImage"
    }
    
    enum ProfileStatus {
        static let Pending = "pending"
        static let Verified = "verified"
        static let Rejected = "rejected"
    }
    enum AvatarStatus {
        static let NewUpload = "new_upload"
        static let UnderVerification = "under_verification"
        static let Verified = "verified"
        static let Rejected = "rejected"
    }
    
    enum Subscription {
        static let Purchased = "purchased"
        static let Failed = "failed"
        static let Restored = "restored"
    }
    
    enum ProductType {
        static let Purchased = "monthly"
        static let Failed = "sixmonthly"
        static let Restored = "annually"
    }
    
    enum LocationType {
        static let locattionEnable = "Please enable location"
    }
    enum UnblockType {
        static let unblockMessage = "Do you want to unblock "
    }
    
    
}
