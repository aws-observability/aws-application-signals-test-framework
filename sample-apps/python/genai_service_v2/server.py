# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

import logging

from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from langchain_aws import ChatBedrock
from langgraph.prebuilt import create_react_agent
from langchain_core.tools import tool

BEDROCK_MODEL_ID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"


@tool
def get_clinic_hours() -> str:
    """Get pet clinic operating hours"""
    return "Monday-Friday: 8AM-6PM, Saturday: 9AM-4PM, Sunday: Closed. Emergency services available 24/7."


@tool
def get_emergency_contact() -> str:
    """Get emergency contact information"""
    return "Emergency Line: (555) 123-PETS. For life-threatening emergencies, call immediately."


@tool
def get_specialist_referral(specialty: str) -> str:
    """Get information about specialist referrals"""
    specialists = {
        "nutrition": "Dr. Smith - Pet Nutrition Specialist (ext. 201)",
        "surgery": "Dr. Johnson - Veterinary Surgeon (ext. 202)",
        "dermatology": "Dr. Brown - Pet Dermatologist (ext. 203)",
        "cardiology": "Dr. Davis - Veterinary Cardiologist (ext. 204)",
    }
    return specialists.get(specialty.lower(), "Please call (555) 123-PETS for specialist referral information.")


@tool
def get_appointment_availability() -> str:
    """Check current appointment availability"""
    return "Appointments available: Today 3:00 PM, Tomorrow 10:00 AM and 2:30 PM. Call (555) 123-PETS to schedule."


@tool
def get_vaccination_records(pet_name: str) -> str:
    """Look up vaccination records for a pet by name"""
    records = {
        "buddy": "Buddy (Golden Retriever): Rabies (2024-03), DHPP (2024-03), Bordetella (2024-06). Next due: Rabies 2025-03.",
        "whiskers": "Whiskers (Tabby Cat): Rabies (2024-05), FVRCP (2024-05). Next due: FVRCP 2025-05.",
        "max": "Max (German Shepherd): Rabies (2024-01), DHPP (2024-01), Lyme (2024-04). Next due: DHPP 2025-01.",
    }
    return records.get(pet_name.lower(), f"No vaccination records found for '{pet_name}'. Please verify the pet name or call (555) 123-PETS.")


@tool
def estimate_treatment_cost(treatment: str) -> str:
    """Get estimated cost for a treatment or procedure"""
    costs = {
        "checkup": "General checkup: $50-$75",
        "vaccination": "Vaccination package: $85-$120",
        "dental cleaning": "Dental cleaning: $200-$350",
        "spay": "Spay surgery: $250-$400",
        "neuter": "Neuter surgery: $200-$350",
        "xray": "X-ray imaging: $150-$250",
        "blood work": "Blood panel: $100-$200",
        "microchip": "Microchip implant: $45-$60",
    }
    return costs.get(treatment.lower(), f"For pricing on '{treatment}', please call (555) 123-PETS for a personalized estimate.")


SYSTEM_PROMPT = """You are a helpful assistant at our pet clinic. Keep responses brief - 2-3 sentences max.
Always greet the user with "Hello, welcome to our pet clinic!" before answering.
For emergencies, immediately provide emergency contact information.
You have access to tools for clinic hours, emergency contacts, specialist referrals, appointments, vaccination records, and treatment cost estimates."""


def create_agent():
    llm = ChatBedrock(model_id=BEDROCK_MODEL_ID)
    tools = [
        get_clinic_hours,
        get_emergency_contact,
        get_specialist_referral,
        get_appointment_availability,
        get_vaccination_records,
        estimate_treatment_cost,
    ]
    return create_react_agent(llm, tools, prompt=SYSTEM_PROMPT)


agent = create_agent()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def chat(request):
    body = await request.json()
    message = body.get("message", "")

    logger.info("X" * 1_200_000)

    response = agent.invoke({"messages": [("human", message)]})
    return JSONResponse({"response": response["messages"][-1].content})


async def health(request):
    return JSONResponse({"status": "ok"})


app = Starlette(routes=[
    Route("/chat", chat, methods=["POST"]),
    Route("/health", health, methods=["GET"]),
])