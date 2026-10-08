//
//  DatePickPopUp.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 11/05/24.
//

import Foundation
import UIKit

extension FlirtCustomPopUp:UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {

    //    func setDOBSelectionUI(){
    //        self.button2.isUserInteractionEnabled = false
    //        self.birthdateView.isHidden = false
    //        [self.monthTextField,self.dayTextField,self.yearTextField].enumerated().forEach { index,textField in
    //            let placeholderText: String
    //            switch index {
    //            case 0:
    //                placeholderText = "MM"
    //            case 1:
    //                placeholderText = "DD"
    //            case 2:
    //                placeholderText = "YYYY"
    //            default:
    //                fatalError("Unhandled text field index")
    //            }
    //            setPlaceholderText(text: placeholderText, textField: textField)
    //            //            self.setupDatePicker()
    //
    //        }
    //    }


    //    BirthDate Section
    func setPlaceholderText(text:String,textField:UITextField){
        // Create attributed placeholder text
        let attributedPlaceholder = NSAttributedString(string:text, attributes: [
            NSAttributedString.Key.font: UIFont.fredoka(.regular, size: 13), // Set the font size
            NSAttributedString.Key.foregroundColor: UIColor.placeholderText // Set the placeholder color
        ])
        // Set attributed placeholder text
        textField.attributedPlaceholder = attributedPlaceholder
    }


    func createCalender(){
        if #available(iOS 16.0, *) {
            let calenderViews = UICalendarView()
            calenderViews.translatesAutoresizingMaskIntoConstraints = false
            calenderViews.calendar = .current
            calenderViews.locale = .current
            calenderViews.fontDesign = .rounded
            calenderViews.delegate = self
            calenderViews.tintColor = AppColor.Punch
            let dateSelection = UICalendarSelectionSingleDate(delegate: self)
            // Set the initial selected date to a date 18 years ago from today
            let eighteenYearsAgo = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
            dateSelection.selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: eighteenYearsAgo)
            self.selectedDOB = eighteenYearsAgo
            calenderViews.selectionBehavior = dateSelection
            self.calenderView.addSubview(calenderViews)
            NSLayoutConstraint.activate([
                calenderViews.leadingAnchor.constraint(equalTo: self.calenderView.leadingAnchor, constant: 5),calenderViews.trailingAnchor.constraint(equalTo: self.calenderView.trailingAnchor, constant:-5),
                calenderViews.topAnchor.constraint(equalTo: self.calenderView.topAnchor, constant: 0),
                calenderViews.bottomAnchor.constraint(equalTo: self.calenderView.bottomAnchor, constant: 0),
                calenderViews.heightAnchor.constraint(equalToConstant: 410),
            ])
            self.calenderView.layoutIfNeeded()
            self.selectedDateCompoent = Calendar.current.dateComponents([.year, .month], from: Date())
        } else {
            // Fallback on earlier versions
        }
    }

    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {

        self.selectedDateCompoent = dateComponents
        self.setSelectedDate(newDateComponents: dateComponents)
    }

    func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
        print(calendarView.visibleDateComponents)

        var newDateComponents = DateComponents()
        newDateComponents.day = self.selectedDateCompoent?.day
        newDateComponents.month = calendarView.visibleDateComponents.month
        newDateComponents.year = calendarView.visibleDateComponents.year
        self.setSelectedDate(newDateComponents: newDateComponents)
    }

    func setSelectedDate(newDateComponents:DateComponents?){
        self.selectedDateCompoent = newDateComponents
        guard let selectedDate = newDateComponents, let eighteenYearsAgo = Calendar.current.date(byAdding: .year, value: -18, to: Date()),
              Calendar.current.date(from: selectedDate) != nil,
              Calendar.current.date(from: selectedDate)! < eighteenYearsAgo else {
//            if self.ageLimitLabel.isHidden == true {
                self.showAgeLimitLabel()
//            }
            self.saveDOBButton.isUserInteractionEnabled = false
            self.saveDOBButton.backgroundColor = AppColor.Punch.withAlphaComponent(0.5)
            // If the selected date is not at least 18 years before today, return without changing anything
            return
        }
        self.selectedDOB = Calendar.current.date(from: selectedDate)!
        print(self.selectedDOB as Any)
//        if self.ageLimitLabel.isHidden == false {
            self.hideAgeLimitLabel()
//        }
    }

    func showAgeLimitLabel(){
        self.ageLimitLabel.alpha = 1
        //        UIView.animate(withDuration: 0.3){
        //            self.ageLimitLabel.isHidden = false
        //        }
        //        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)   {
        //            self.ageLimitLabel.alpha = 1
        //        }
        saveDOBButton.isUserInteractionEnabled = false
        saveDOBButton.backgroundColor = AppColor.Punch.withAlphaComponent(0.5)
    }

    func hideAgeLimitLabel(){
        self.ageLimitLabel.alpha = 0
        //        UIView.animate(withDuration: 0.3) {
        //            self.ageLimitLabel.isHidden = true
        //        }
        self.saveDOBButton.isUserInteractionEnabled = true
        self.saveDOBButton.backgroundColor = AppColor.Punch
    }

    @available(iOS 16.0, *)
    func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
        return nil
    }
}

























//    set datepickerUI to select DOB
//    func setupDatePicker() {
//        datePicker = UIDatePicker()
//        datePicker?.locale = .current
//        datePicker?.datePickerMode = .date
//        datePicker?.frame.size = CGSize(width: 0, height: 100)
//        datePicker?.maximumDate = Date()
//        let currentDate = Date()
//        if let sixteenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: currentDate) {
//            datePicker?.maximumDate = sixteenYearsAgo
//        }
//        datePicker?.addTarget(self, action: #selector(dateChanged(_:)), for: UIControl.Event.valueChanged)
//        if #available(iOS 13.4, *) {
//            datePicker?.preferredDatePickerStyle = .wheels
//        }else{
//            // Fallback on earlier versions
//        }
//        monthTextField.inputView = datePicker
//        dayTextField.inputView = datePicker
//        yearTextField.inputView = datePicker
//        //        datePicker?.tintColor = .blue
//
//        self.monthTextField.delegate = self
//        self.dayTextField.delegate = self
//        self.yearTextField.delegate = self
//
//        monthTextField.addTarget(self, action: #selector(openDatePicker(_:)), for: .touchDown)
//        dayTextField.addTarget(self, action: #selector(openDatePicker(_:)), for: .touchDown)
//        yearTextField.addTarget(self, action: #selector(openDatePicker(_:)), for: .touchDown)
//    }

//    @objc func openDatePicker(_ sender: UITextField) {
//        sender.becomeFirstResponder()
//    }
//
//    @objc func dateChanged(_ datePicker: UIDatePicker) {
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd"
//        dayTextField.text = dateFormatter.string(from: datePicker.date)
//
//        dateFormatter.dateFormat = "MM"
//        monthTextField.text = dateFormatter.string(from: datePicker.date)
//
//        dateFormatter.dateFormat = "yyyy"
//        yearTextField.text = dateFormatter.string(from: datePicker.date)
//    }

//    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
//        if textField == dayTextField || textField == monthTextField || textField == yearTextField {
//            textField.inputView = datePicker
//            let toolbar = UIToolbar()
//            toolbar.sizeToFit()
//            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
//            toolbar.setItems([doneButton], animated: true)
//            textField.inputAccessoryView = toolbar
//        }
//        return true
//    }
//
//    func textFieldDidEndEditing(_ textField: UITextField) {
//        self.setSaveButtonUI()
//    }
//

//
//    //    Date picker done button
//    @objc func doneButtonTapped() {
//        self.setSaveButtonUI()
//        self.contentView.endEditing(true)
//    }

