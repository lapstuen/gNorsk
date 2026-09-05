//
//  APIConfig.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/7/25.
//


enum APIConfig {
    // TODO: Flytt til sikker lokasjon eller environment variables
    static let googleAPIKey = "AIzaSyBEgeRWhaA5dF21yJrUZAHvdX0y2CH3kUI"
    static let azureAPIKey = "YOUR_AZURE_KEY_HERE"
    static let azureRegion = "eastus"
}

/*
 # Test API-nøkkelen din i Terminal:
 curl -H "Content-Type: application/json" \
      -d '{"input":{"text":"สวัสดี"},"voice":{"languageCode":"th-TH","name":"th-TH-Neural2-C"},"audioConfig":{"audioEncoding":"MP3"}}' \
      "https://texttospeech.googleapis.com/v1/text:synthesize?key=AIzaSyBEgeRWhaA5dF21yJrUZAHvdX0y2CH3kUI"
 
 */
